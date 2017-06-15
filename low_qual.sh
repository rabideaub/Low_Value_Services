#!/bin/bash
#sas low_qual_build.sas -memsize 64G -sortsize 56G -sumsize 56G
#sas low_qual_procs2.sas -memsize 64G -sortsize 56G -sumsize 56G
sas calc_costs.sas -memsize 64G -sortsize 56G -sumsize 56G
sas year_num_denom2.sas -memsize 64G -sortsize 56G -sumsize 56G
sas weight_test.sas -memsize 64G -sortsize 56G -sumsize 56G
sas demog_table.sas -memsize 64G -sortsize 56G -sumsize 56G
#cd /schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Data
#st low_value_beneficiary.sas7bdat low_value_beneficiary.dta -y
#stata-mp -b low_qual_models.do