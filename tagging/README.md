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

1. Deploy Tag Engine in your Governance Project by following Tag Engine's [deployment guide](https://github.com/GoogleCloudPlatform/datacatalog-tag-engine/blob/cloud-run/README.md). Information below will help you choose parameters when deploying:
    - Designate `$TAG_CREATOR_SA` and `$CLOUD_RUN_SA` as the service accounts to be used on the tag engine deployment. You can access their values by running `echo $TAG_CREATOR_SA` and `echo $CLOUD_RUN_SA`.
    - Replace `TAG_ENGINE_SA` in `tagengine.ini` with `CLOUD_RUN_SA` variable value.
    - Replace `TAG_CREATOR_SA` in `tagengine.ini` with `TAG_CREATOR_SA` variable value.
    - Replace `TAG_ENGINE_PROJECT` in `tagengine.ini` with `PROJECT_ID_GOV` variable value.
    - Replace `FIRESTORE_PROJECT` in `tagengine.ini` with `PROJECT_ID_GOV` variable value.
    - Replace `FIRESTORE_DB` in `tagengine.ini` with `default` value.
    - Replace `TAG_HISTORY_PROJECT` in `tagengine.ini` with `PROJECT_ID_GOV` variable value.
    - Replace `TAG_HISTORY_DATASET` in `tagengine.ini` with `tag_history_logs` value.
    - Replace `JOB_METADATA_PROJECT` in `tagengine.ini` with `PROJECT_ID_GOV` variable value.
    - Create `deploy/terraform.tfvars` with the following values, remember to replace placeholder values with values from your environment:

        ```terraform
        bigquery_project = "PROJECT_ID_DATA"
        data_catalog_project = "PROJECT_ID_DATA"
        firestore_project = "PROJECT_ID_GOV"
        tag_engine_project = "PROJECT_ID_GOV"
        tag_engine_sa = "CLOUD_RUN_SA"
        tag_creator_sa = "TAG_CREATOR_SA"

        firestore_database = default
        csv_bucket = "REPLACE_WITH_BUCKET_NAME" # bucket is created when following tag engine readme, 
        ```

    - There is a known issue with the Terraform deployment with tag engine. If you encounter the error `The requested URL was not found on this server` when you try to create a configuration from the API, the issue is that the container didn't build correctly. Try to rebuild and redeploy the Cloud Run API service with this command:

        ```bash
        cd datacatalog-tag-engine
        gcloud run deploy tag-engine-api \
            --source . \
            --platform managed \
            --region $REGION \
            --no-allow-unauthenticated \
            --ingress=all \
            --memory=4G \
            --timeout=60m \
            --service-account=$CLOUD_RUN_SA
        ```

    - Assign additional roles to `TAG_CREATOR_SA`:

        ```bash
        gcloud projects add-iam-policy-binding $PROJECT_ID_GOV --role="roles/bigquery.dataViewer" --member="serviceAccount:$TAG_CREATOR_SA"

        gcloud projects add-iam-policy-binding $PROJECT_ID_GOV --role="roles/bigquery.user" --member="serviceAccount:$TAG_CREATOR_SA"
        
        gcloud projects add-iam-policy-binding $PROJECT_ID_GOV --role="roles/datacatalog.viewer" --member="serviceAccount:$TAG_CREATOR_SA"

        gcloud projects add-iam-policy-binding $PROJECT_ID_DATA --role="roles/datacatalog.tagTemplateUser" --member="serviceAccount:$TAG_CREATOR_SA"
        ```

1. Set environment variables:

    ```bash
    export TAG_ENGINE_URL=`gcloud run services describe tag-engine-api --format="value(status.url)" --project=$PROJECT_ID_GOV`
    export IAM_TOKEN=$(gcloud auth print-identity-token)
    export OAUTH_TOKEN=$(gcloud auth application-default print-access-token)
    ```

1. Retrieve the Data Taxonomy Name by running the command below:

    ```bash
    gcloud data-catalog taxonomies list --location=$REGION --project=$PROJECT_ID_GOV
    ```

1. Take note of the `name` field, retrieved by the command above and insert it in the shell variable below:

    ```bash
    export TAXONOMY_NAME=<INSERT_TAXONOMY_HERE>
    ```

1. Replace placeholders in `tag_engine_configs`:

    ```bash
    #Linux
    sed -i tag_engine_configs/*.json \
        -e "s:REPLACE_WITH_YOUR_DATA_TAXONOMY:$TAXONOMY_NAME:g" \
        -e "s/PROJECT_ID_DATA/$PROJECT_ID_DATA/g" \
        -e "s/PROJECT_ID_GOV/$PROJECT_ID_GOV/g" \
        -e "s/REGION/$REGION/g" \
        -e "s/PROJECT_NUMBER_DATA/$PROJECT_NUMBER_DATA/g"
    ```

1. Give permission for current authenticated user to impersonate Tag Creator:

    ```bash
    gcloud iam service-accounts add-iam-policy-binding $TAG_CREATOR_SA \
        --project=$PROJECT_ID_GOV \
        --role="roles/iam.serviceAccountUser" \
        --member="user:$AUTHENTICATED_USER"
    ```

1. Create the tag engine configurations, take note of the `config_uuid` that each command outputs, it will be used later on when orchestrating the workflow:

    ```bash
    # Create config outputs directory
    export OUT_DIR=/tmp/tag-engine-config-outputs
    mkdir -p $OUT_DIR

    curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
    -d @tag_engine_configs/data_sensitivity_crm.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/data_sensitivity_crm_output.json

    curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
    -d @tag_engine_configs/data_sensitivity_hr.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/data_sensitivity_hr_output.json

    curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
    -d @tag_engine_configs/data_sensitivity_oltp.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/data_sensitivity_oltp_output.json

    curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
    -d @tag_engine_configs/data_sensitivity_sales.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/data_sensitivity_sales_output.json

    curl -X POST $TAG_ENGINE_URL/create_sensitive_column_config \
    -d @tag_engine_configs/data_sensitivity_finwire.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/data_sensitivity_finwire_output.json
    ```

    ```bash
    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cdmc_controls_crm.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cdmc_controls_crm_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cdmc_controls_hr.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cdmc_controls_hr_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cdmc_controls_oltp.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cdmc_controls_oltp_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cdmc_controls_sales.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cdmc_controls_sales_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cdmc_controls_finwire.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cdmc_controls_finwire_output.json
    ```

    ```bash
    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/security_policy_crm.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/security_policy_crm_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/security_policy_hr.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/security_policy_hr_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/security_policy_oltp.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/security_policy_oltp_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/security_policy_sales.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/security_policy_sales_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/security_policy_finwire.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/security_policy_finwire_output.json
    ```

    ```bash
    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cost_metrics_crm.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cost_metrics_crm_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cost_metrics_hr.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cost_metrics_hr_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cost_metrics_oltp.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cost_metrics_oltp_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cost_metrics_sales.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cost_metrics_sales_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/cost_metrics_finwire.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/cost_metrics_finwire_output.json
    ```

    ```bash
    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/completeness_crm.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/completeness_crm_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/completeness_hr.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/completeness_hr_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/completeness_oltp.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/completeness_oltp_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/completeness_sales.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/completeness_sales_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/completeness_finwire.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/completeness_finwire_output.json
    ```

    ```bash
    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/correctness_crm.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/correctness_crm_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/correctness_hr.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/correctness_hr_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/correctness_oltp.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/correctness_oltp_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/correctness_sales.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/correctness_sales_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_column_config \
    -d @tag_engine_configs/correctness_finwire.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/correctness_finwire_output.json
    ```

    ```bash
    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/impact_assessment_crm.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/impact_assessment_crm_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/impact_assessment_hr.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/impact_assessment_hr_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/impact_assessment_oltp.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/impact_assessment_oltp_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/impact_assessment_sales.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/impact_assessment_sales_output.json

    curl -X POST $TAG_ENGINE_URL/create_dynamic_table_config \
    -d @tag_engine_configs/impact_assessment_finwire.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/impact_assessment_finwire_output.json
    ```

    ```bash
    curl -X POST $TAG_ENGINE_URL/create_export_config \
    -d @tag_engine_configs/export_all_tags.json \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "oauth_token: $OAUTH_TOKEN" | tee $OUT_DIR/tag_export_output.json
    ```

#### Part 5: Tag update orchestration

1. Enable `workflows.googleapis.com` on Governance Project:

    ```bash
    gcloud services enable workflows.googleapis.com --project=$PROJECT_ID_GOV
    ```

1. Open each yaml file under the `/orchestration` folder, and replace the `config_uuid` values starting on line 9 with the actual values you received from the previous step when creating the configs.

1. Replace `REPLACE_WITH_TAG_ENGINE_URL` placeholder with your `TAG_ENGINE_URL`:

    ```bash
    # Linux
    sed "s#REPLACE_WITH_TAG_ENGINE_URL#$TAG_ENGINE_URL#g" -i orchestration/*.yaml
    ```

1. You'll also need to replace the project id values in the yaml files.

    ```bash
    # Linux
    sed "s/PROJECT_ID_GOV/$PROJECT_ID_GOV/g" -i orchestration/*.yaml
    ```

1. To deploy a workflow, you need to specify a service account that you'd like the workflow to run as. We recommend you use the cloud run service account which you created for running Tag Engine. This will be referred to as CLOUD_RUN_SA in the commands below.

    ```bash
    cd orchestration

    gcloud workflows deploy tag-updates-data-sensitivity --location=$REGION \
    --source=tag_updates_data_sensitivity.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy tag-updates-cdmc-controls --location=$REGION \
    --source=tag_updates_cdmc_controls.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy tag-updates-security-policy --location=$REGION \
    --source=tag_updates_security_policy.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy tag-updates-cost-metrics --location=$REGION \
    --source=tag_updates_cost_metrics.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy tag-updates-completeness --location=$REGION \
    --source=tag_updates_completeness.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy tag-updates-correctness --location=$REGION \
    --source=tag_updates_correctness.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy tag-updates-impact-assessment --location=$REGION \
    --source=tag_updates_impact_assessment.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy tag-exports-all-templates --location=$REGION \
    --source=tag_exports_all_templates.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy oauth-token --location=$REGION \
    --source=oauth_token.yaml --service-account=$CLOUD_RUN_SA

    gcloud workflows deploy caller_workflow --location=$REGION \
    --source=caller_workflow.yaml --service-account=$CLOUD_RUN_SA
    ```

1. Assign `roles/workflows.invoker` and `roles/cloudbuild.builds.editor` to `CLOUD_RUN_SA`:

    ```bash
    gcloud projects add-iam-policy-binding $PROJECT_ID_GOV --member="serviceAccount:$CLOUD_RUN_SA" --role="roles/workflows.invoker"

    gcloud projects add-iam-policy-binding $PROJECT_ID_GOV --member="serviceAccount:$CLOUD_RUN_SA" --role="roles/cloudbuild.builds.editor"   
    ```

1. Open the Cloud Workflows UI `<https://console.cloud.google.com/workflows?project=PROJECT_ID_GOV>` and create a job trigger for the `caller_workflow`. The `caller_workflow` executes all of the other workflows in the right sequence. The `caller_workflow` takes about ~70 minutes to run. By creating the job trigger, you are scheduling the `caller_workflow` to run on a regular interval.
