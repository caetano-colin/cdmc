configs_dir=$1
categories=('crm' 'hr' 'oltp' 'sales' 'finwire')
external_categories=('cdmc_controls' 'completeness' 'correctness' 'cost_metrics' 'data_sensitivity' 'impact_assessment' 'security_policy')
orchestration_dir=./orchestration


for external_category in ${external_categories[@]}; do
  for category in ${categories[@]}; do
    filename="${external_category}_${category}_output.json"
    config_uuid=$(cat $configs_dir/$filename | jq -r '.config_uuid')
    echo sed "s/REPLACE_WITH_${category^^}_${external_category^^}_CONFIG_UUID/$config_uuid/" -i $orchestration_dir/tag_updates_${external_category}.yaml
  done
done


tag_export_config_file=$configs_dir/tag_export_output.json
tag_export_placeholder_file=$orchestration_dir/tag_exports_all_templates.yaml
config_uuid=$(cat $tag_export_config_file | jq -r '.config_uuid')
echo sed "s/REPLACE_WITH_TAG_EXPORT_CONFIG_UUID/$config_uuid/" -i $tag_export_placeholder_file