# Hello world tekton CI/CD sample application

A simple node application that can be deployed with [CI-toolchain](https://github.ibm.com/one-pipeline/compliance-ci-toolchain) and [CD-toolchain](https://github.ibm.com/one-pipeline/compliance-cd-toolchain).


## Documentation and troubleshoot guideline:

Can be found [here](https://github.ibm.com/one-pipeline/docs)

## ZAP

ZAP in is an open-source web application security scanner that can be used to scan for both API an UI vulnerabilities.

The Hello-Compliance-App leverages the SCC version of the ZAP scanner. This entails an interface wrapped around the original open-source ZAP scanner that simplfies the setup to run the scans, particulary APIs that require IAM authentication.

API Scans
The open-source Zap scanner uses the application's Swagger yaml document for identifying the APIs to be scanned. The SCC version uses a json format version with a wrapper. This wrapper indicates which of the listed APIs should be scanned (the provided example scans all) and provides details for IAM authentication. The API scanner only excepts Swagger docs in json format with the above wrapper. Yaml needs to be converted

UI Scans
A test suite is required such as a Protector UI E2E suite to navigate the UI which will guide the Zap scanner to the UI endpoints.  

By default whether the scan is run inline or asynchronously, the scanning process is run in a Docker in Docker manner. This removes the need to set up a running instance of the Zap containers in your cluster. This default behavious can be changed (see trigger_zap_scan script) but required cluster details to be provided.

### Contents

1) zap-ui-test is a sample UI test suite provided by the SCC team

2) zap-custom-scripts provides sample scripts for customising an API and UI scan.

### Zap Custom scripts 
There are two sample scripts. 
1) API: The Zap API related scripts are used to generate the json wrapper. 

2) UI: The sample script can provide a means to extract any required parameters needed by the UI test suite

### Running the scans
The trigger_zap_scans script outlines an example of setting up both an API scan followed by a UI scan. This can readily be customized.
