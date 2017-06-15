libname out "/sch-projects/dua-data-projects/OPTUM/rabideau/Data";
%let out = /sch-projects/dua-data-projects/OPTUM/rabideau/Data;

/*Create macro for cost variables*/
%let cost_vars = cst_lv_bone cst_homoc cst_coag cst_pth cst_chest_x 
				 cst_cardio_x cst_arthro cst_pft cst_stress cst_ct_sinus cst_scan_sync cst_scan_head cst_eeg_head cst_back 
				 cst_carotid_scan_asymp cst_carotid_scan_sync cst_cardio_stress cst_coronary cst_renal_angio cst_carotid_end 
				 cst_ivc cst_vertebro cst_neuro cst_diagnostic cst_preoperative cst_musculo cst_cardio cst_lv 
				 cst_t3_test cst_spine_inj cst_pf_image cst_OH_vitamin cst_vit_d cst_pap cst_cyst cst_hpv

				 cst_lv_bone_s cst_homoc_s cst_coag_s cst_pth_s cst_chest_x_s cst_cardio_x_s cst_pft_s 
				 cst_stress_s cst_ct_sinus_s cst_scan_sync_s cst_scan_head_s cst_eeg_head_s cst_back_s 
				 cst_carotid_scan_asymp_s cst_carotid_scan_sync_s cst_cardio_stress_s cst_coronary_s 
				 cst_renal_angio_s cst_carotid_end_s cst_ivc_s cst_vertebro_s cst_arthro_s 
				 cst_neuro_s cst_diagnostic_s cst_preoperative_s cst_musculo_s cst_cardio_s cst_lv_s
				 cst_t3_test_s cst_spine_inj_s cst_pf_image_s cst_OH_vitamin_s /*cst_vit_d_s cst_pap_s*/ cst_cyst_s cst_hpv_s;

/*Read in beneficiary-level data*/
data lv_bene_wt;
	length age_cat $ 5;
	set out.low_value_beneficiary_median;
	if 18<=age<=24 then age_cat='18-24';
	if 25<=age<=44 then age_cat='25-44';
	if 45<=age<=64 then age_cat='45-64';
run;

/*Determine the yearly distribution by age and gdr_cd - compare to national representation to create weights*/
proc freq data=lv_bene_wt;
	tables age_cat*gdr_cd / out=age_sex;
	where age_cat~='' & gdr_cd~='' & year=2013 & elig_2013=1;
run;

proc freq data=lv_bene_wt;
	tables elig_2013 / out=elig_benes;
	where year=2013;
run;

proc print data=age_sex;
run;
proc print data=elig_benes;
run;

/*Hardcoded population based on MEPS nationally representative sample found online here: http://meps.ahrq.gov/mepsweb/data_stats/MEPSnetHC/datasource.
  To get results, select appropriate year and the variables 'AGE', 'SEX', 'INSURCOV', and 'PRVEV[YR]'. Set INSURCOV=1, PRVEV[YR]=1, 18<=AGE<=64*/
data _null_;
	set elig_benes end=last;
	if last then do;
		pop_ratio=132750404/COUNT;
		call symput('pop_ratio',trim(left(pop_ratio)));
	end;
run;

/*Hardcoded values are based on distributions from MEPS nationally representative sample found online here: http://meps.ahrq.gov/mepsweb/data_stats/MEPSnetHC/datasource.
  To get results, select appropriate year and the variables 'AGE', 'SEX', 'INSURCOV', and 'PRVEV[YR]'. Set INSURCOV=1, PRVEV[YR]=1, 18<=AGE<=64*/
data age_sex_wt;
	set age_sex;
	if age_cat='18-24' & gdr_cd='M' then weight=7.24/PERCENT;
	if age_cat='18-24' & gdr_cd='F' then weight=6.90/PERCENT;
	if age_cat='25-44' & gdr_cd='M' then weight=19.91/PERCENT;
	if age_cat='25-44' & gdr_cd='F' then weight=21.06/PERCENT;
	if age_cat='45-64' & gdr_cd='M' then weight=21.69/PERCENT;
	if age_cat='45-64' & gdr_cd='F' then weight=23.21/PERCENT;

	weight_pop_ratio=weight*&pop_ratio.;
run;

proc print data=age_sex_wt;
run;

/*Merge the weight values onto the beneficiary level dataset - calculate weighted costs*/
proc sort data=age_sex_wt; by age_cat gdr_cd; run;
proc sort data=lv_bene_wt; by age_cat gdr_cd; run;

data lv_beneficiary_wt;
	merge lv_bene_wt
		  age_sex_wt;
	by age_cat gdr_cd;
	array cstnumer {*} &cost_vars.;
	do i=1 to dim(cstnumer);
		cstnumer[i]=cstnumer[i]*weight_pop_ratio;
	end;
run;

title "Collapsed Costs at Beneficiary Level - Weighted";
proc print data=lv_beneficiary_wt (obs=20);
	var patid year age_cat gdr_cd weight_pop_ratio cst_lv;
run;

proc sort data=lv_beneficiary_wt; by patid; run;

/*Collapse down to the year level*/
proc means data=lv_beneficiary_wt nway noprint;
	class year;
	var &cost_vars. tot_procs;
	output out=lv_year sum=;
run;

title "Collapsed Costs at Year Level - Weighted";
proc print data=lv_year;
	var year cst_lv cst_lv_bone;
run;
title;

/*Create the low value procedure proportions for each individual lv procedure*/
data lv_year;
	set lv_year (drop=_TYPE_ rename=(_FREQ_=tot_patients));
run;

/*Transpose the data to make it more manageable*/
proc transpose data=lv_year out=year_xpose name=Procedure prefix=year;
 id year;
 var tot_procs tot_patients &cost_vars.;
run;

/*Group the data to make building a table less of a manual effort*/
data year_xpose;
	length LV_Group $ 15;
	set year_xpose;

	/*Neuro*/
	if prxmatch("/ct_sinus/",procedure)>0 | prxmatch("/scan_sync/",procedure)>0 | prxmatch("/scan_head/",procedure)>0 |
	   prxmatch("/eeg_head/",procedure)>0 
	   then LV_Group="Head and Neurologic Diagnostic Imaging and Testing";



	/*Diagnostic*/
	if prxmatch("/homoc/",procedure)>0 | prxmatch("/coag/",procedure)>0 |
	   prxmatch("/t3/",procedure)>0 | prxmatch("/hpv/",procedure)>0 | prxmatch("/cyst/",procedure)>0 |
	   prxmatch("/pap/",procedure)>0 | prxmatch("/vit_d/",procedure)>0 | prxmatch("/vitamin/",procedure)>0 |
	   prxmatch("/pth/",procedure)>0
	   then LV_Group="Diagnostic and Preventive Testing";


	/*Cardio*/
	if prxmatch("/cardio_stress/",procedure)>0 | prxmatch("/coronary/",procedure)>0 | prxmatch("/renal_angio/",procedure)>0 |
	   prxmatch("/carotid_end/",procedure)>0  | prxmatch("/ivc/",procedure)>0 | prxmatch("/carotid_scan/",procedure)>0 
	   then LV_Group="Cardiovascular Testing and Procedures";


	/*Preoperative*/
	if prxmatch("/chest_x/",procedure)>0 | prxmatch("/cardio_x/",procedure)>0 | prxmatch("/pft/",procedure)>0 |
	   (prxmatch("/stress/",procedure)>0 & prxmatch("/cardio/",procedure)=0)
	   then LV_Group="Preoperative Testing";


	/*Musculo*/
	if prxmatch("/back/",procedure)>0 | prxmatch("/bone/",procedure)>0 | prxmatch("/vertebro/",procedure)>0 | 
	   prxmatch("/arthro/",procedure)>0 | prxmatch("/spine/",procedure)>0 | prxmatch("/pf_image/",procedure)>0
	   then LV_Group="Musculoskeletal Diagnostic Testing and Procedures";

	/*General*/
	if prxmatch("/physicians/",procedure)>0 | prxmatch("/tot_procs/",procedure)>0 | prxmatch("/bene_stays/",procedure)>0 |
	   prxmatch("/tot_patients/",procedure)>0  then LV_Group="_General"; 

	sorter=substr(procedure,1,3);

	*format procedure $proc.;
run;

proc sort data=year_xpose; by sorter LV_Group Procedure; run;

/*Append the 1 obs total cost dataset onto the final output dataset*/
data low_value_procs;
	length age_cat $5;
	set out.low_value_procs2 (where=(18<=age<65) keep=age gdr_cd year elig_2011 elig_2012 elig_2013 std_cost);
	if 18<=age<=24 then age_cat='18-24';
	if 25<=age<=44 then age_cat='25-44';
	if 45<=age<=64 then age_cat='45-64';
run;

title "Procedure Level";
proc print data=low_value_procs (obs=20);
	var age_cat gdr_cd std_cost year;
run;
title;

proc sort data=low_value_procs; by age_cat gdr_cd; run;

data cst_tot (keep=Procedure LV_Group year2011 year2012 year2013 sorter);
	merge low_value_procs 
		  age_sex_wt
		  end=last;
	by age_cat gdr_cd;
	retain year2011 year2012 year2013;
	Procedure="tot_cost";
	LV_Group="_General";
	sorter="tot";
	std_cost=std_cost*weight_pop_ratio;
	if year=2011 & elig_2011=1 then year2011=sum(year2011,std_cost);
	if year=2012 & elig_2012=1 then year2012=sum(year2012,std_cost);
	if year=2013 & elig_2013=1 then year2013=sum(year2013,std_cost);
	if last then output;
run;

title "Total Costs";
proc print data=cst_tot;
run;
title;

data year_xpose;
	set year_xpose
		cst_tot;
run;

/*********************
PRINT CHECK
*********************/
/*Output a sample of each of the datasets to an excel workbook*/
ods tagsets.excelxp file="&out./year_num_denom_wt_med.xml" style=sansPrinter;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="Beneneficiary Level" frozen_headers='yes');
proc print data=lv_beneficiary_wt (obs=1000);
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="Year Level" frozen_headers='yes');
proc print data=lv_year (obs=1000);
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="Year Transposed" frozen_headers='yes');
proc print data=year_xpose (obs=1000);
run;
ods tagsets.excelxp close;
/*********************
CHECK END
*********************/

