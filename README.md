# Jenkins pipeline for WordPress on AWS (example)

A Jenkins pipeline I built at StackIT Solutions for CliXX, a WordPress retail site on AWS. It's shared here as a worked example, and the CI/CD lessons on [kwamib.dev](https://kwamib.dev/resources/cicd) refer to it.

This is a cleaned copy of the original repository. The pipeline, Dockerfile and Ansible playbooks are as I wrote them, with these changes:

- AWS account IDs replaced with AWS's documentation placeholder, `123456789012`
- The S3 bucket and security group replaced with placeholders
- `Jenkinsfile-1` renamed to `Jenkinsfile`
- Left out: the WordPress files, the database dump, and the scripts for assuming AWS roles

It won't run as it is: it depends on AWS accounts, an RDS snapshot, SonarQube and Slack that this copy doesn't include.

## What the pipeline does

1. Cleans the workspace and checks out the code
2. Scans the code with SonarQube, and stops the build if the quality gate fails
3. Restores the database on Amazon RDS from a snapshot, using Ansible
4. Loads a WordPress database dump from S3 and points the site at the server's public address
5. Builds the WordPress image, tagged `1.0.<build number>-<short commit SHA>`, and runs it
6. Asks a person whether to tear the environment down
7. Pushes the image to Amazon ECR

Most stages post to Slack as they start and finish, and the `post` block cleans up and reports a failed, unstable or aborted build.

## What I'd change now

I've kept the pipeline as it was so the lessons can show the before and after. Things I'd do differently:

- Pass secrets to `sh` with single quotes (`'$SONAR_TOKEN'`), not Groovy string interpolation, so they never appear in the command Jenkins builds. The Restore DB Dump stage already does this the right way with `MYSQL_PWD`.
- Push the image to ECR straight after it's built and checked, not after the tear-down question.
- Add a smoke test after the container starts, such as a `curl` that checks the site answers.
- Add tests alongside the SonarQube scan.
- Deploy to a separate server, not the Jenkins machine itself.
