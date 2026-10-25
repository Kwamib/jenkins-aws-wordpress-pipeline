pipeline {
    agent any

    parameters {
        string(name: 'YOUR_NAME', defaultValue: 'Mayowa B', description: 'Engineer responsible for this build')
        string(name: 'DB_NAME', defaultValue: 'wordpressdb', description: 'Database Name')
        choice(name: 'DB_INSTANCE_CLASS', choices: ['db.t3.micro', 'db.t3.small', 'db.t3.medium'], description: 'RDS Instance Class')
        string(name: 'SNAPSHOT_ID', defaultValue: 'arn:aws:rds:us-east-1:123456789012:snapshot:clixx-db-development-snapshot', description: 'RDS Snapshot Identifier')
        booleanParam(name: 'SKIP_DB_RESTORE', defaultValue: false, description: 'Skip database restoration')
    }

    environment {
        VERSION = "1.0.${BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'local'}"
        PATH = "${PATH}:${getSonarPath()}"
        DB_USERNAME = 'wordpressuser'
        AWS_DEFAULT_REGION = 'us-east-1'
        RDS_INSTANCE_ID = 'clixxdb-restored'
        ECR_REGISTRY = '123456789012.dkr.ecr.us-east-1.amazonaws.com'  // AWS ECR registry URI
        ECR_REPOSITORY = 'clixx-image'                               // ECR repo name
    }

    options {
        skipDefaultCheckout false
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
                slackSend color: '#439FE0', message: "*CHECKOUT COMPLETED* by `${params.YOUR_NAME}`: Job `${env.JOB_NAME}` [#${env.BUILD_NUMBER}]\n<${env.BUILD_URL}|Open Build>"
            }
        }

        stage('Notify Start') {
            steps {
                slackSend color: '#439FE0', message: "*BUILD STARTED* by `${params.YOUR_NAME}`: Job `${env.JOB_NAME}` [#${env.BUILD_NUMBER}]\n<${env.BUILD_URL}|Open Build>"
            }
        }

        stage('Sonarqube Scan') {
            steps {
                script {
                    def scannerHome = tool 'sonarqube'
                    withCredentials([string(credentialsId: 'SONAR_TOKEN', variable: 'SONAR_TOKEN')]) {
                        withEnv(['SONAR_SCANNER_OPTS=--add-opens java.base/java.lang=ALL-UNNAMED']) {
                            withSonarQubeEnv('SonarQubeScanner') {
                                sh """
                                    ${scannerHome}/bin/sonar-scanner \\
                                        -Dsonar.projectKey=CliXX-App \\
                                        -Dsonar.login=${SONAR_TOKEN}
                                """
                            }
                        }
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    script {
                        def qualityGate = waitForQualityGate()
                        slackSend color: (qualityGate.status == 'OK' ? 'good' : 'danger'),
                                  message: "*Quality Gate:* `${qualityGate.status}` for `${env.JOB_NAME}` [#${env.BUILD_NUMBER}]\n<${env.BUILD_URL}|Open Build>"
                        if (qualityGate.status != 'OK') {
                            error("Quality Gate failed: ${qualityGate.status}")
                        }
                    }
                }
            }
        }

        stage('Restore RDS from Snapshot') {
            when {
                expression { return !params.SKIP_DB_RESTORE }
            }
            steps {
                withCredentials([string(credentialsId: 'DB_PASSWORD', variable: 'DB_MASTER_PASSWORD')]) {
                    script {
                        def start = System.currentTimeMillis()
                        slackSend color: '#439FE0', message: "*Restore RDS from Snapshot* started by `${params.YOUR_NAME}`"

                        sh """
                            set -euo pipefail

                            python3 -m venv python3-virtualenv
                            source python3-virtualenv/bin/activate

                            pip install --upgrade pip
                            pip install "ansible>=7.0.0" boto3 botocore

                            cat <<EOF > requirements.yml
collections:
    - name: amazon.aws
      version: "6.1.0"
EOF

                            ansible-galaxy collection install -r requirements.yml --force

                            ansible-playbook deploy_db_ansible/deploy_db.yml \\
                              -e "instance_id=${RDS_INSTANCE_ID}" \\
                              -e "db_snapshot=${params.SNAPSHOT_ID}" \\
                              -e "db_instance_class=${params.DB_INSTANCE_CLASS}" \\
                              -e "db_name=${params.DB_NAME}" \\
                              -e "db_master_password=${DB_MASTER_PASSWORD}"
                        """

                        def duration = (System.currentTimeMillis() - start) / 1000
                        slackSend color: 'good', message: "*Restore RDS from Snapshot* completed in `${duration}s`"
                    }
                }
            }
        }

        stage('Extract DB Endpoint') {
            steps {
                script {
                    def start = System.currentTimeMillis()
                    slackSend color: '#439FE0', message: "*Extract DB Endpoint* started..."

                    def props = readYaml file: 'deploy_db_ansible/db.setup'
                    env.DB_ENDPOINT = props.db_endpoint
                    echo "Using DB endpoint: ${env.DB_ENDPOINT}"

                    def duration = (System.currentTimeMillis() - start) / 1000
                    slackSend color: 'good', message: "*Extract DB Endpoint* completed in `${duration}s`. Endpoint: `${env.DB_ENDPOINT}`"
                }
            }
        }

        stage('Download DB Dump from S3') {
            steps {
                script {
                    slackSend color: '#439FE0', message: "*Download DB Dump from S3* started for build ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open Build>)"

                    sh '''
                        aws s3 cp s3://example-config-bucket/wordpressdb.sql ./wordpressdb.sql --region us-east-1
                    '''

                    slackSend color: 'good', message: "*Download DB Dump from S3* completed successfully for build ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open Build>)"
                }
            }
        }

        stage('Restore DB Dump') {
            steps {
                script {
                    slackSend color: '#439FE0', message: "*Restore DB Dump* started for build ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open Build>)"

                    withCredentials([string(credentialsId: 'DB_PASSWORD', variable: 'MYSQL_PWD')]) {
                        sh """
                            mysql -h ${env.DB_ENDPOINT} -u ${env.DB_USERNAME} -e "CREATE DATABASE IF NOT EXISTS ${params.DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
                            mysql -h ${env.DB_ENDPOINT} -u ${env.DB_USERNAME} ${params.DB_NAME} < wordpressdb.sql
                        """
                    }

                    slackSend color: 'good', message: "*Restore DB Dump* completed successfully for build ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open Build>)"
                }
            }
        }

        stage('Update WordPress Site URL') {
            steps {
                script {
                    slackSend color: '#439FE0', message: "*Update WordPress Site URL* started\n<${env.BUILD_URL}|Open Build>"

                    def token = sh(
                        script: "curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' -s",
                        returnStdout: true
                    ).trim()
                    def publicDns = sh(
                        script: "curl -H 'X-aws-ec2-metadata-token: ${token}' -s http://169.254.169.254/latest/meta-data/public-hostname",
                        returnStdout: true
                    ).trim()
                    echo "Public DNS detected: ${publicDns}"

                    withCredentials([string(credentialsId: 'DB_PASSWORD', variable: 'DB_MASTER_PASSWORD')]) {
                        sh """
                          mysql -h ${env.DB_ENDPOINT} -u ${env.DB_USERNAME} -p"${DB_MASTER_PASSWORD}" ${params.DB_NAME} -e \\
                            "UPDATE wp_options SET option_value = 'http://${publicDns}' WHERE option_name IN ('siteurl', 'home');"
                        """
                    }

                    slackSend color: 'good', message: "*Update WordPress Site URL* completed successfully\nSite URL: http://${publicDns}\n<${env.BUILD_URL}|Open Build>"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    def start = System.currentTimeMillis()
                    slackSend color: '#439FE0', message: "*Build Docker Image* started..."

                    sh """
                        docker image prune -f
                        docker build . -t clixx-image:${VERSION} -t clixx-image:latest
                        docker images | grep clixx-image | grep -E "${VERSION}|latest"
                    """

                    def duration = (System.currentTimeMillis() - start) / 1000
                    slackSend color: 'good', message: "*[COMPLETED]* Docker Image Built with tag `clixx-image:${VERSION}` in `${duration}s`"
                }
            }
        }

        stage('Run Docker Container') {
            steps {
                script {
                    def start = System.currentTimeMillis()
                    slackSend color: '#439FE0', message: "*Run Docker Container* started..."

                    withCredentials([string(credentialsId: 'DB_PASSWORD', variable: 'RDS_MASTER_PASSWORD')]) {
                        def dbName = params.DB_NAME
                        def dbUser = env.DB_USERNAME
                        def dbPassword = RDS_MASTER_PASSWORD
                        def dbHost = env.DB_ENDPOINT
                        def imageVersion = VERSION

                        sh """
                            set -euo pipefail

                            if docker ps -a --format '{{.Names}}' | grep -q '^clixx-cont\$'; then
                                docker stop clixx-cont || true
                                docker rm clixx-cont || true
                            fi

                            docker run -d -p 80:80 --name clixx-cont \\
                                -e WORDPRESS_DB_NAME='${dbName}' \\
                                -e WORDPRESS_DB_USER='${dbUser}' \\
                                -e WORDPRESS_DB_PASSWORD='${dbPassword}' \\
                                -e WORDPRESS_DB_HOST='${dbHost}' \\
                                clixx-image:${imageVersion}
                        """
                    }

                    def duration = (System.currentTimeMillis() - start) / 1000
                    slackSend color: 'good', message: "*Run Docker Container* completed in `${duration}s`. Container: `clixx-cont`"
                }
            }
        }

        stage('Tear Down CliXX Docker Image and Database') {
            steps {
                script {
                    def userInput = input(
                        id: 'confirm',
                        message: 'Tear Down Environment?',
                        parameters: [
                            [$class: 'BooleanParameterDefinition', defaultValue: false, description: 'Tear Down Environment?', name: 'confirm']
                        ]
                    )
                    if (userInput) {
                        slackSend color: '#FFA500', message: "*Tear Down Started* by `${params.YOUR_NAME}` for build `${env.BUILD_NUMBER}`"
                        
                        sh '''
                            python3 -m venv python3-virtualenv
                            source python3-virtualenv/bin/activate
                            pip install --upgrade pip
                            pip install boto3 botocore ansible

                            ansible-playbook $WORKSPACE/deploy_db_ansible/delete_db.yml

                            deactivate

                            docker stop clixx-cont || true
                            docker rm clixx-cont || true
                        '''
                        
                        slackSend color: 'good', message: "*Tear Down Completed* by `${params.YOUR_NAME}` for build `${env.BUILD_NUMBER}`"
                    } else {
                        slackSend color: '#808080', message: "*Tear Down Cancelled* by `${params.YOUR_NAME}` for build `${env.BUILD_NUMBER}`"
                        echo "Tear down cancelled by user"
                    }
                }
            }
        }

        stage('Ensure ECR Repository Exists') {
            steps {
                script {
                    sh """
                        aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region us-east-1 || \\
                        aws ecr create-repository --repository-name ${ECR_REPOSITORY} --region us-east-1
                    """
                }
            }
        }

        stage('Push Docker Image to ECR') {
            steps {
                script {
                    slackSend color: '#439FE0', message: "*Push Docker Image to ECR* started..."

                    sh """
                        aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        docker tag clixx-image:${VERSION} ${ECR_REGISTRY}/${ECR_REPOSITORY}:${VERSION}
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${VERSION}

                        docker tag clixx-image:latest ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest
                    """

                    slackSend color: 'good', message: "*Push Docker Image to ECR* completed successfully."
                }
            }
        }
    }

    post {
        always {
            sh '''
                rm -rf python3-virtualenv || true
                rm -f deploy_db_ansible/db.setup || true
                rm -f wordpressdb.sql || true
            '''
        }
        failure {
            slackSend color: 'danger', message: "*BUILD FAILED* by `${params.YOUR_NAME}`: ${env.BUILD_URL}"
        }
        unstable {
            slackSend color: 'warning', message: "*BUILD UNSTABLE* by `${params.YOUR_NAME}`: ${env.BUILD_URL}"
        }
        aborted {
            slackSend color: '#808080', message: "*BUILD ABORTED* by `${params.YOUR_NAME}`: ${env.BUILD_URL}"
        }
    }
}

def getSonarPath() {
    def SonarHome = tool name: 'sonarqube', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
    return SonarHome
}

def getDockerPath() {
    def DockerHome = tool name: 'docker-inst', type: 'dockerTool'
    return DockerHome
}