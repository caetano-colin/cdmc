### Tagging

The tagging aspects of the solution consist of four parts:

1. Creating the Data Catalog tag templates and policy tag taxonomy
1. Create the policy tables in BigQuery and the remote BigQuery functions
1. Deploying and configuring Tag Engine
1. Deploying and scheduling the tag update orchestration workflow

This guide assumes that you have already completed the data ingestion deployment, the data scanning deployment, and the data quality deployment.

#### Part 1: Data Catalog tag templates and policy tag taxonomy

1. Create the Data Catalog tag templates by running these commands:

  ```bash
  cd tag_templates
  pip install -r requirements.txt
  python create_template.py $PROJECT_ID_DATA $REGION cdmc_controls.yaml
  python create_template.py $PROJECT_ID_DATA $REGION completeness_template.yaml
  python create_template.py $PROJECT_ID_DATA $REGION correctness_template.yaml
  python create_template.py $PROJECT_ID_DATA $REGION cost_metrics.yaml
  python create_template.py $PROJECT_ID_DATA $REGION data_sensitivity.yaml
  python create_template.py $PROJECT_ID_DATA $REGION impact_assessment.yaml
  python create_template.py $PROJECT_ID_DATA $REGION security_policy.yaml
  python create_template.py $PROJECT_ID_DATA $REGION uniqueness_template.yaml
  cd ..
  ```

2. Create policy tag:

    1. Navigate to `policy_tags` directory and install requirements.

        ```bash
        cd policy_tags
        pip install -r requirements.txt
        ```

    1. Create new `taxonomy.yaml` file based on template.

        ```bash
        cp taxonomy.yaml.example taxonomy.yaml
        ```

    1. Replace placeholders on taxonomy.yaml file:

        ```bash
        #Linux
        sed -i taxonomy.yaml \
          -e "s/<PROJECT_ID_GOV>/$PROJECT_ID_GOV/g" \
          -e "s/<REGION>/$REGION/g" \
          -e "s/<AUTHENTICATED_USER>/$AUTHENTICATED_USER/g"
        ```

        > Important: The command above assumes you have the variables available at your shell, if you don't have them available run `environment-variables.sh` script.

    1. Run `create_policy_tag_taxonomy.py` script

        ```bash
        python create_policy_tag_taxonomy.py taxonomy.yaml
        cd ..
        ```

        > Note: If you receive a `409 Requested entity already exists`, this might be due to a taxonomy with the name `sensitive_data_classification` already exists within your organization. In that case, modify the `name` field at `taxonomy.yaml` and re-run the python script.

#### Part 2: Policy tables

1. Navigate to `tagging/ddl` directory:

    ```bash
    cd ddl
    ```

1. Create policy datasets:

    ```bash
    bq mk --location=$REGION --dataset data_classification
    bq mk --location=$REGION --dataset data_retention
    bq mk --location=$REGION --dataset impact_assessment
    bq mk --location=$REGION --dataset entitlement_management
    bq mk --location=$REGION --dataset security_policy
    ```

1. Replace placeholders in `sql` files with values from your environment.

    ```bash
    # Linux
    sed "s/PROJECT_ID_DATA/$PROJECT_ID_DATA/g" -i create_impact_assessment_tables.sql
    sed "s/PROJECT_ID_DATA/$PROJECT_ID_DATA/g" -i create_populate_entitlement_tables.sql
    ```

    > Important: The command above assumes you have the variables available at your shell, if you don't have them available run `environment-variables.sh` script.

1. Run the `sql` queries below to create and populate tables.

    ```bash
    bq query --use_legacy_sql=false < create_data_classification_tables.sql
    bq query --use_legacy_sql=false < create_data_retention_tables.sql
    bq query --use_legacy_sql=false < create_impact_assessment_tables.sql
    bq query --use_legacy_sql=false < create_populate_entitlement_tables.sql
    bq query --use_legacy_sql=false < create_security_policy_tables.sql
    bq query --use_legacy_sql=false < information_schema_view.sql
    ```

    > Note: The sql files contains fictional data for demonstration purposes.

#### Part 3: Creating Remote Functions

For each subfolder in `/remote_functions`, create a Python Cloud Function with `requirements.txt` and `main.py`. Once the function has been created, wrap it with a remote BigQuery function using the `create_remote_function.sh`. For more details on creating remote BigQuery functions, refer to the [product documentation](https://cloud.google.com/bigquery/docs/remote-functions#create_a_remote_function).

Before proceeding with the steps below, ensure you have run `environment-variables.sh` script and have variables like `$REGION`, `$PROJECT_ID_DATA` available at your shell.

1. Create `remote_functions` dataset in Governance project:

    ```bash
    bq mk --location=$REGION --project_id=$PROJECT_ID_GOV --dataset remote_functions
    ```

1. Set the default project to the Governance project:

    ```bash
    gcloud config set project $PROJECT_ID_GOV
    ```

1. Create `get_bytes_transferred` function:

    ```bash
    pushd remote_functions/bytes_transferred

    gcloud functions deploy get_bytes_transferred \
    --runtime python37 \
    --trigger-http \
    --no-allow-unauthenticated \
    --ingress-settings internal-and-gclb \
    --entry-point event_handler \
    --source ./function \
    --set-env-vars REGION=$REGION,PROJECT_ID_DATA=$PROJECT_ID_DATA

    source ./create_remote_function.sh

    popd
    ```

1. Create `get_location_policy` function:

    ```bash
    pushd remote_functions/location_policy

    gcloud functions deploy get_location_policy \
    --runtime python37 \
    --trigger-http \
    --no-allow-unauthenticated \
    --ingress-settings internal-and-gclb \
    --entry-point event_handler \
    --source ./function \
    --set-env-vars REGION=$REGION,PROJECT_ID_DATA=$PROJECT_ID_DATA

    source ./create_remote_function.sh
    popd
    ```

1. Create `get_masking_rule` function:

    ```bash
    pushd remote_functions/masking_rule

    gcloud functions deploy get_masking_rule \
    --runtime python37 \
    --trigger-http \
    --no-allow-unauthenticated \
    --ingress-settings internal-and-gclb \
    --entry-point event_handler \
    --source ./function \
    --set-env-vars REGION=$REGION,PROJECT_ID_DATA=$PROJECT_ID_DATA

    source ./create_remote_function.sh
    popd
    ```

1. Create `get_table_encryption_method` function:

    ```bash
    pushd remote_functions/table_encryption_method

    gcloud functions deploy get_table_encryption_method \
    --runtime python37 \
    --trigger-http \
    --no-allow-unauthenticated \
    --ingress-settings internal-and-gclb \
    --entry-point event_handler \
    --source ./function \
    --set-env-vars REGION=$REGION,PROJECT_ID_DATA=$PROJECT_ID_DATA

    source ./create_remote_function.sh
    popd
    ```

1. Create `get_ultimate_source` function:

    ```bash
    pushd remote_functions/ultimate_source

    gcloud functions deploy get_ultimate_source \
    --runtime python37 \
    --trigger-http \
    --no-allow-unauthenticated \
    --ingress-settings internal-and-gclb \
    --entry-point process_request \
    --source ./function \
    --set-env-vars REGION=$REGION,PROJECT_ID_DATA=$PROJECT_ID_DATA

    source ./create_remote_function.sh
    popd
    ```

1. The resource locations Organization Policy Service constraint defines the Google Cloud regions that you can store data in. By default, the architecture sets the constraint on the Confidential data project, you can do that by following de series of steps below:

    - Create a `policy.yaml` file with the following content, remember to replace `PROJECT_ID_DATA` string with your environment `PROJECT_ID_DATA` value:

        ```yaml
        name: projects/PROJECT_ID_DATA/policies/gcp.resourceLocations
        spec:
          rules:
          - values:
                allowedValues:
                - in:us-central1-locations
        ```

    - Run the command below on the same directory as `policy.yaml`:

        ```bash
        gcloud org-policies set-policy policy.yaml
        ```

1. Retrieve Cloud Function Service Account e-mail:

    ```bash
    CF_SA_EMAIL=$(gcloud functions describe get_bytes_transferred --format=json | python3 -c "import sys, json; print(json.load(sys.stdin)['serviceAccountEmail'])")
    echo $CF_SA_EMAIL
    ```

1. Assign BigQuery Data Viewer, BigQuery Job User, and Organization Policy Viewer permissions on Confidential Data project for the Service Account:

    ```bash
    gcloud projects add-iam-policy-binding $PROJECT_ID_DATA --role="roles/bigquery.dataViewer" --member="serviceAccount:$CF_SA_EMAIL"

    gcloud projects add-iam-policy-binding $PROJECT_ID_DATA --role="roles/bigquery.jobUser" --member="serviceAccount:$CF_SA_EMAIL"

    gcloud projects add-iam-policy-binding $PROJECT_ID_DATA --role="roles/orgpolicy.policyViewer" --member="serviceAccount:$CF_SA_EMAIL"

    gcloud projects add-iam-policy-binding $PROJECT_ID_DATA --role="roles/cloudkms.viewer" --member="serviceAccount:$CF_SA_EMAIL"

    gcloud projects add-iam-policy-binding $PROJECT_ID_DATA --role="roles/datalineage.viewer" --member="serviceAccount:$CF_SA_EMAIL"
    ```

1. Enable `orgpolicy.googleapis.com` API on Governance Project:

    ```bash
    gcloud services enable orgpolicy.googleapis.com
    ```

1. It is recommended to open your BigQuery Studio and perform some sample queries, to ensure that the remote functions are working as expected, remember to replace placeholders (PROJECT_ID_GOV, PROJECT_ID_DATA, PROJECT_NUMBER_DATA) with values from your environment:

    ```sql
    select `PROJECT_ID_GOV`.remote_functions.get_location_policy('PROJECT_ID_DATA');
    ```

    ```sql
    select `PROJECT_ID_GOV`.remote_functions.get_table_encryption_method('PROJECT_ID_DATA', 'hr', 'Employee');
    ```

    ```sql
    select `PROJECT_ID_GOV`.remote_functions.get_ultimate_source('PROJECT_ID_DATA', PROJECT_NUMBER_DATA, 'us-central1', 'crm', 'NewCust');
    ```

#### Part 4: Tag Engine deployment and configuration

1. Deploy Tag Engine in your GCP project by following Tag Engine's [deployment guide](https://github.com/GoogleCloudPlatform/datacatalog-tag-engine/blob/cloud-run/README.md).

1. Set environment variables:

```bash
export TAG_ENGINE_URL=`gcloud run services describe tag-engine --format="value(status.url)"`
export IAM_TOKEN=$(gcloud auth print-identity-token)
export OAUTH_TOKEN=$(gcloud auth application-default print-access-token)
```

7. Configure tag history:

```
curl -X POST $TAG_ENGINE_URL/configure_tag_history \
 -d '{"bigquery_region":"$REGION", "bigquery_project":"$PROJECT_ID_GOV", "bigquery_dataset":"tag_history_logs", "enabled":true}' \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

Replace the `bigquery_region`, `bigquery_project`, and `bigquery_dataset` with your own values.

8. Create the tag engine configurations:

```
curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
 -d @tag_engine_configs/data_sensitivity_crm.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
 -d @tag_engine_configs/data_sensitivity_hr.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
 -d @tag_engine_configs/data_sensitivity_sales.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
 -d @tag_engine_configs/data_sensitivity_finwire.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

```
curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cdmc_controls_crm.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cdmc_controls_hr.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cdmc_controls_oltp.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cdmc_controls_sales.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cdmc_controls_finwire.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

```
curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/security_policy_crm.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/security_policy_hr.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/security_policy_oltp.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/security_policy_sales.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/security_policy_finwire.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

```
curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cost_metrics_crm.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cost_metrics_hr.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cost_metrics_oltp.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cost_metrics_sales.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/cost_metrics_finwire.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

```
curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/completeness_crm.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/completeness_hr.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/completeness_oltp.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/completeness_sales.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/completeness_finwire.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

```
curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/correctness_crm.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/correctness_hr.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/correctness_oltp.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/correctness_sales.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
 -d @tag_engine_configs/correctness_finwire.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

```
curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/impact_assessment_crm.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/impact_assessment_hr.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/impact_assessment_oltp.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/impact_assessment_sales.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"

curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
 -d @tag_engine_configs/impact_assessment_finwire.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

```
curl -X POST $TAG_ENGINE_URL/create_export_config \
 -d @tag_engine_configs/export_all_tags.json \
 -H "Authorization: Bearer $IAM_TOKEN" \
 -H "oauth_token: $OAUTH_TOKEN"
```

#### Part 5: Tag update orchestration

9. Enable the Cloud Workflows API.

10. Open each yaml file under the `/orchestration` folder, and replace the `config_uuid` values starting on line 9 with the actual values you received from the previous step when creating the configs. You'll also need to replace the project id values in the `caller_workflow.yaml` file.

10. Deploy the workflows:

To deploy a workflow, you need to specify a service account that you'd like the workflow to run as. We recommend you use the cloud run service account which you created for running Tag Engine. This will be referred to as CLOUD_RUN_SA in the commands below.

```
gcloud workflows deploy tag-updates-data-sensitivity --location=$REGION \
 --source=tag_updates_data_sensitivity.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy tag-updates-cdmc-controls --location=$REGION \
 --source=tag_updates_cdmc_controls.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy tag-updates-security-policy --location=$REGION \
 --source=tag_updates_security_policy.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy tag-updates-cost-metrics --location=$REGION \
 --source=tag_updates_cost_metrics.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy tag-updates-completeness --location=$REGION \
 --source=tag_updates_completeness.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy tag-updates-correctness --location=$REGION \
 --source=tag_updates_correctness.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy tag-updates-impact-assessment --location=$REGION \
 --source=tag_updates_impact_assessment.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy tag-exports-all-templates --location=$REGION \
 --source=tag_exports_all_templates.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy oauth-token --location=$REGION \
 --source=oauth_token.yaml --service-account=CLOUD_RUN_SA

gcloud workflows deploy caller_workflow --location=$REGION \
 --source=caller_workflow.yaml --service-account=CLOUD_RUN_SA
```

11. Open the Cloud Workflows UI and create a job trigger for the `caller_workflow`. The `caller_workflow` executes all of the other workflows in the right sequence. The `caller_workflow` takes about ~70 minutes to run. By creating the job trigger, you are scheduling the `caller_workflow` to run on a regular interval.
