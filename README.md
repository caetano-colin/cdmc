# Google Cloud CDMC Reference Architecture

This repository contains the CDMC reference architecture for Google Cloud.
This guide provides the detailed instructions and technical artefacts required to stand up a Google Cloud architecture compliant with the 14 Controls of the EDMCouncil [Cloud
Data Management Capabilities (CDMC)](https://edmcouncil.org/frameworks/cdmc/).

This architecture has been tested for compliance against the controls by an indipendent third party, and has achieved compliance on the controls.

This architecture should be seen as an example guide. Each user who wishes to work towards CDMC compliance for their organisation will need to customise the architecture to their needs and undergo a separate CDMC assessment on their solution.

## Prerequisites

### GCP Setup

#### Obtain application default credentials (ADC)

In order to run the scripts in the repositories, you will need to set up the
application default credentials for any machine used to run the script.

```bash
gcloud auth application-default login
```

You will be asked to login and enter an authorization code.

This command will place the credentials file in the following location:

* Linux, macOS: `$HOME/.config/gcloud/application_default_credentials.json`
* Windows: `%APPDATA%\gcloud\application_default_credentials.json`

#### Infrastructure creation

The CDMC architecture relies on a number of GCP component which need to be provisioned.

* *Optional*: create a GCP Folder:

    ```bash
    gcloud resource-manager folders create --display-name=CDMC-LABS
    ```

##### GCP Projects setup

This guide relies on two projects being available:

* A project to store the data, and run the controls against. For example `cdmc-confdata`. You can create the data project with this command, make sure you replace `cdmc-confdata` with another value:

    ```bash
    gcloud projects create cdmc-confdata --folder [FOLDER_ID]
    ```

* A project to act as your data governance one. For example `cdmc-gov`.
You can create the data governance project with this command, make sure you replace `cdmc-gov` with another value:

    ```bash
    gcloud projects create cdmc-gov --folder [FOLDER_ID]
    ```

##### Infrastructure configuration

The `setup.sh` script creates the necessary GCP components in the Data and Gov projects created above.

Before running the `setup.sh` script, make sure you have created and customised your `environment-variables.sh` file, using `environment-variables.example` as a template.

```bash
cp environment-variables.example environment-variables.sh
```

Open `environment-variables.sh` with a text editor and replace the following values below with values from your environment:

```bash
export PROJECT_ID_DATA="REPLACE WITH YOUR VALUE"
export PROJECT_ID_GOV="REPLACE WITH YOUR VALUE"
export REGION="REPLACE WITH YOUR VALUE"
```

Once you have customised the `environment-variables.sh`, make sure to execute it:

```bash
source environment-variables.sh
```

Then create the infrastructure using the `setup.sh` convenience script. The script will:

* Activate required API's on the projects.
* Create bucket for sample data upload.
* Assign required IAM permissions.
* Create required Service Accounts.

```bash
source setup.sh
```

### Virtual Environment

It is advisable to create a virtual environment to install the required python dependencies in
the machine you are running any script from.

```bash
# Install virtual environment and activate
python3 -m venv .venv
source .venv/bin/activate
```

## Deployment Guide

Each component of the reference architecture has its own deployment guide. To deploy the entire reference architecture, follow the steps in each of the guides. There are 7 guides in total listed below, make sure you follow them on the order below:

1. [data ingestion](./data-ingestion/README.md)
1. [data scanning](./data-scanning/README.md)
1. [data quality](./data-quality/README.md)
1. [tagging](./tagging/README.md)
1. [record manager](https://github.com/GoogleCloudPlatform/bigquery-record-manager/blob/main/README.md)
1. [report engine](./report-engine/README.md)
1. [dashboard](./dashboard/README.md)
