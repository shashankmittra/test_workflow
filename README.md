<p align="center">
    <a href="https://cloud.ibm.com">
        <img src="https://cloud.ibm.com/media/docs/developer-appservice/resources/ibm-cloud.svg" height="100" alt="IBM Cloud">
    </a>
</p>

<p align="center">
    <a href="https://cloud.ibm.com">
        <img src="https://img.shields.io/badge/IBM%20Cloud-powered-blue.svg" alt="IBM Cloud">
    </a>
    <img src="https://img.shields.io/badge/platform-nodejs-lightgrey.svg?style=flat" alt="Node.js">
    <a href="https://cloud.ibm.com/docs/devsecops">
        <img src="https://img.shields.io/badge/DevSecOps-enabled-blue.svg?style=flat" alt="DevSecOps">
    </a>
</p>

# Create and deploy a Node.js Sample Application using IBM Cloud DevSecOps

> **DISCLAIMER**: This is a guideline sample application and is used for demonstrative and illustrative purposes of Node.js application deployed using IBM Cloud DevSecOps Continuous Integration (CI) and Continuous Deployment (CD) pipelines. This is not a production ready code.

## Contents
- [Scope](#scope)
- [Run the sample](#run-the-sample)
- [Create DevSecOps toolchains](#create-devsecops-toolchains)
- [Additional information](#additional-information)

## Scope
This sample contains a simple Node.js microservice that can be deployed to a Kubernetes cluster and provides a simple front-end.

## Run the sample
- Prerequisites:
  - Node.js installed on your machine.
- Download the source code
  ```
  git clone <git_url>
  cd hello-compliance-app
  ```
- Installing dependencies by running `npm install` from the root folder to install the app’s dependencies.
- Run `npm start` to start the app.
- Access the running app in a browser at http://localhost:8080

## Create DevSecOps toolchains

### Pre-requisites

- An IBM Cloud account needs to be setup
- A Kubernetes cluster exists to deploy the application

More information at [DevSecOps Tutorial - Set up prerequisites](https://cloud.ibm.com/docs/devsecops?topic=devsecops-tutorial-cd-devsecops)

### Toolchains setup

The DevSecOps toolchains to create and deploy this Node.js sample to IBM Cloud with DevSecOps CI can be created using the following link: [DevSecOps CI toolchain](https://cloud.ibm.com/devops/setup/deploy?repository=https%3A%2F%2Fus-south.git.cloud.ibm.com%2Fopen-toolchain%2Fcompliance-ci-toolchain&env_id=ibm:yp:us-south).

The DevSecOps CD can be created using the following link: [DevSecOps CD toolchain](https://cloud.ibm.com/devops/setup/deploy?repository=https%3A%2F%2Fus-south.git.cloud.ibm.com%2Fopen-toolchain%2Fcompliance-cd-toolchain&env_id=ibm:yp:us-south).

### Customized scripts for DevSecOps pipelines
The source code of the sample contains a [.pipeline-config.yaml](/.pipeline-config.yaml) file and scripts located in the [scripts](./scripts/) folder.
The `.pipeline-config.yaml` file is the core configuration file that is used by DevSecOps CI, CD and CC pipelines for all of the stages in the pipeline run processes.
Those scripts can be customized if needed just like the `.pipeline-config.yaml` content.

### Configuration of customized stages and scripts
Note: default scripts invoked in various stages of the pipelines are provided by the [commons base image](https://us-south.git.cloud.ibm.com/open-toolchain/compliance-commons) and can be configured using specific properties, as described in the documentation [Pipeline parameters](https://cloud.ibm.com/docs/devsecops?topic=devsecops-cd-devsecops-pipeline-parm)

The sections below describe additional parameters (specific to these customized scripts) used to configure the [`scripts`](./scripts/) used in this sample.

#### containerize stage
| Property | Default | Description | Required |
| -------- | :-----: | ----------- | :------: |
| `registry-domain` | | the container registry URL domain that is used to build and tag the image. Useful when using private-endpoint container registry. | |

#### deploy stage
| Property | Default | Description | Required |
| -------- | :-----: | ----------- | :------: |
| `deployment-file` | `deployment_os.yml` or `deployment_iks.yml` according to the kind of Kubernetes cluster | Kubernetes deployment file to apply to the target kubernetes cluster | |
| `cookie-secret` | `mycookiesecret` | cookie secret value for the deployment secret | |
| `deploy-ibmcloud-api-key` | Default to the value of `ibmcloud-api-key` | specific IBM Cloud API key to be used for the deployment to the cluster. | |

#### dynamic-scan stage
| Property | Default | Description | Required |
| -------- | :-----: | ----------- | :------: |
| `opt-in-dynamic-scan` | | To enable the OWASP Zap scan. | |
| `opt-in-dynamic-api-scan` | | To enable the OWASP Zap API scan. | |
| `opt-in-dynamic-api-scan` | | To enable the OWASP Zap UI scan. | |

#### release stage
| Property | Default | Description | Required |
| -------- | :-----: | ----------- | :------: |
| `skip-inventory-update-on-failure` | | if set, the inventory update will be done only if there is no failure in the compliance checks | |

### Detect secrets

Detect secrets check is performed as part of the PullRequest pipeline and Continuous Integration pipelines so this repository includes a [.secrets.baseline](.secrets.baseline) to identify baseline for secrets check.

More information at [Configuring Detect secrets scans](https://cloud.ibm.com/docs/devsecops?topic=devsecops-cd-devsecops-detect-secrets-scans)

Note: detect-secret is configured as a pre-commit hook for this sample repository. See [.pre-commit-config.yaml](.pre-commit-config.yaml)

### CRA Scanning

This repository includes a [.cra/.cveignore](.cra/.cveignore) file that is used by Code Risk Analyzer (CRA) in IBM Cloud Continuous Delivery. This file helps address vulnerabilities that are found by CRA until a remediation is available, at which point the vulnerabilities will be addressed in the respective package versions. CRA keeps the code in this repository free of known vulnerabilities, and therefore helps make applications that are built on this code more secure. If you are not using CRA, you can safely ignore this file.

## Additional information

### Documentation
- [DevSecOps tutorial - Set-up prerequites](https://cloud.ibm.com/docs/devsecops?topic=devsecops-tutorial-cd-devsecops)
- [DevSecOps tutorial - Set-up a DevSecOps CI toolchain](https://cloud.ibm.com/docs/devsecops?topic=devsecops-tutorial-ci-toolchain)
- [DevSecOps tutorial - Set-up a DevSecOps CD toolchain](https://cloud.ibm.com/docs/devsecops?topic=devsecops-tutorial-cd-toolchain)
- [DevSecOps Continuous Integration pipeline](https://cloud.ibm.com/docs/devsecops?topic=devsecops-cd-devsecops-ci-pipeline)

### Troubleshooting
Documentation can be found [here](https://cloud.ibm.com/docs/ContinuousDelivery?topic=ContinuousDelivery-troubleshoot-devsecops).

### Report a problem or looking for help
Get help directly from the IBM Cloud development teams by joining us on [Slack](https://join.slack.com/t/ibm-devops-services/shared_invite/zt-1znyhz8ld-5Gdy~biKLe233Chrvgdzxw).
