libname dat "/sch-projects/dua-data-projects/OPTUM/rabideau/Data";
libname raw "/sch-data-library/dua-data/OPTUM/Original_data/Data";

data low_value_costs;
	set dat.low_value_procs2 
	(keep=Patid Fst_dt conf_id year diag: proc: std_cost age gdr_cd division D_EDUCATION_LEVEL_CODE
 
		   lv_bone homoc 
		   coag pth chest_x 
		   cardio_x arthro pft stress ct_sinus scan_sync scan_head eeg_head back 
		   carotid_scan_asymp carotid_scan_sync cardio_stress coronary renal_angio carotid_end
		   ivc vertebro neuro diagnostic preoperative musculo cardio lv 
		   t3_test spine_inj pf_image OH_vitamin vit_d pap cyst hpv

		   lv_bone_s homoc_s 
		   coag_s pth_s chest_x_s 
		   cardio_x_s arthro_s pft_s stress_s ct_sinus_s scan_sync_s scan_head_s eeg_head_s back_s 
		   carotid_scan_asymp_s carotid_scan_sync_s cardio_stress_s coronary_s renal_angio_s carotid_end_s
		   ivc_s vertebro_s neuro_s diagnostic_s preoperative_s musculo_s cardio_s lv_s 
		   t3_test_s spine_inj_s pf_image_s OH_vitamin_s /*vit_d_s pap_s*/ cyst_s hpv_s);

	if lv=. then lv=0;
	if 18<=age<65;
	if upcase(gdr_cd)='U' | upcase(division)='UNKNOWN' | upcase(D_EDUCATION_LEVEL_CODE)='U' then delete;
run;

proc freq data=low_value_costs;
	tables lv_bone homoc 
		   coag pth chest_x 
		   cardio_x arthro pft stress ct_sinus scan_sync scan_head eeg_head back 
		   carotid_scan_asymp carotid_scan_sync cardio_stress coronary renal_angio carotid_end
		   ivc vertebro neuro diagnostic preoperative musculo cardio lv 
		   t3_test spine_inj pf_image OH_vitamin vit_d pap cyst hpv

		   lv_bone_s homoc_s 
		   coag_s pth_s chest_x_s 
		   cardio_x_s arthro_s pft_s stress_s ct_sinus_s scan_sync_s scan_head_s eeg_head_s back_s 
		   carotid_scan_asymp_s carotid_scan_sync_s cardio_stress_s coronary_s renal_angio_s carotid_end_s
		   ivc_s vertebro_s neuro_s diagnostic_s preoperative_s musculo_s cardio_s lv_s 
		   t3_test_s spine_inj_s pf_image_s OH_vitamin_s /*vit_d_s pap_s*/ cyst_s hpv_s;
run;

proc sort data=low_value_costs; by Patid Fst_dt descending lv;

data low_value_costs;
	set low_value_costs;
	retain any_lv;
	by Patid Fst_dt;
	if first.Fst_dt then any_lv=(lv~=0);
	if any_lv=1; 
run;

proc print data=low_value_costs (obs=100); run;

proc format;
	value $proc 
	'36415' = 'homoc_s and pth_s'
	'83890'-'83914' = 'coag_s'
	'93303'-'93352' = 'cardio_x_s and cardio_stress_s'
	'94010'-'94799' = 'pft_s'
	'93720'-'93722' = 'pft_s'
	'93000'-'93042' = 'cardio_stress_s'
	'78414'-'78499' = 'cardio_stress_s'
	'75552'-'75564' = 'cardio_stress_s'
	'75571'-'75574' = 'cardio_stress_s'
	'A9500'-'A9700' = 'cardio_stress_s'
	'J0150' = 'cardio_stress_s'
	'J0152' = 'cardio_stress_s'
	'J0280' = 'cardio_stress_s'
	'J1245' = 'cardio_stress_s'
	'J1250' = 'cardio_stress_s'
	'J2785' = 'cardio_stress_s'
	'36010' = 'ivc_s'
	'37620' = 'ivc_s'
	'75825' = 'ivc_s'
	'76937' = 'ivc_s';
run;

/*Variables that need additional coding: homoc coag	pth	cardio_x pft cardio_stress stress coronary ivc*/

/*For these procedures, sum up all costs for specific procedures on the same day as the low value procedure, defined by the format statement above*/
%macro total_cost(var);
	proc sort data=low_value_costs; by Patid Fst_dt descending &var.; 

	data costs_&var. (keep=year &var._day tot_cost std_cost Patid Fst_dt proc_cd rename=(&var._day=&var.))
		 same_day_&var. (keep=proc_cd proc1 proc2 proc3 std_cost);
		length proc_cd_f proc1_f proc2_f proc3_f $30;
		set low_value_costs;

		format proc_cd proc1 proc2 proc3 $proc.;
		proc_cd_f=vvalue(proc_cd);
		proc1_f=vvalue(proc1);
		proc2_f=vvalue(proc2);
		proc3_f=vvalue(proc3);

		retain tot_cost &var._day;
		by Patid Fst_dt;
		if first.Fst_dt then do;
			tot_cost=0;
			&var._day=0;
			if &var.=1 then do;
				&var._day=1;
			end;
		end;
		if &var._day=1 then do; /*Sum up the costs of the claim with the lv proc and the claims with supplmental procs on the same day*/
			if index(proc_cd_f,"&var.")>0 | 
			   index(proc1_f,"&var.")  >0 |
			   index(proc2_f,"&var.")  >0 |
			   index(proc3_f,"&var.")  >0 |
			   &var.=1 then tot_cost=sum(tot_cost,std_cost);
		end;
		/*Output all obs on the same day with an indicated procedure code*/
		if &var._day=1 & (index(proc_cd_f,"&var.")>0 | &var.=1) then output same_day_&var.;

		/*Collapse down to the day level with the collapsed costs*/
		if last.Fst_dt & &var._day=1 then output costs_&var.;
	run;

	/*Collapse down to the patient-year level*/
	proc sort data=costs_&var.; by Patid year; run;

	data costs_&var. (keep=Patid year cst_&var.);
		set costs_&var.;
		retain cst_&var.;
		by Patid year;
		if first.year then do;
			cst_&var.=0;
		end;
		cst_&var.=sum(cst_&var.,tot_cost);
		if last.year then output;
	run;

	proc univariate data=costs_&var.;
		var cst_&var.;
		ods output quantiles=quant_&var.;
	run;

	/*Strip formats from the CPT dataset so we can see the CPT codes*/
    proc datasets lib=work memtype=data;
    	modify same_day_&var.; 
    	attrib _all_ label=' '; 
     	attrib _all_ format=;
	run;

	proc freq data=same_day_&var.;
		tables proc_cd / out=cpt_freqs_&var.;
	run;

	/*Add on the total cost and average cost of each CPT code associated with the procedure*/
	proc sort data=same_day_&var.; by proc_cd; run;

	data proc_costs_&var. (keep=proc_cd proc_cost avg_cost);
		set same_day_&var.;
		retain proc_cost total_count;
		by proc_cd;
		if first.proc_cd then do;
			proc_cost=0;
			total_count=0;
		end;
		proc_cost=sum(proc_cost,std_cost);
		total_count=total_count+1;
		avg_cost=proc_cost/total_count;
		if last.proc_cd then output;
	run;

	/*Merge the costs and the counts of each procedure*/
	data cpt_freqs_&var;
		merge cpt_freqs_&var.
			  proc_costs_&var.;
		by proc_cd;
	run;

	data cpt_freqs_&var.;
		set cpt_freqs_&var.;
		if proc_cd~='';
		if COUNT<11 then do;
			COUNT=.;
			PERCENT=.;
			avg_cost=.;
		end;
	run;

	proc sort data=cpt_freqs_&var.; by descending proc_cost; run;
%mend;
%total_cost(homoc);
%total_cost(coag);
%total_cost(pth);
%total_cost(cardio_x);
%total_cost(pft);
%total_cost(cardio_stress);
%total_cost(stress);
%total_cost(ivc);
%total_cost(homoc_s);
%total_cost(coag_s);
%total_cost(pth_s);
%total_cost(cardio_x_s);
%total_cost(pft_s);
%total_cost(cardio_stress_s);
%total_cost(stress_s);
%total_cost(ivc_s);

/*For these procedures, sum up all costs for all procedures on the same day as the low value procedure*/
%macro total_cost_all(var);
	proc sort data=low_value_costs; by Patid Fst_dt descending &var.; 

	data costs_&var. (keep=year &var._day tot_cost std_cost Patid Fst_dt proc_cd rename=(&var._day=&var.))
		 same_day_&var. (keep=proc_cd proc1 proc2 proc3 std_cost);
		length proc_cd_f proc1_f proc2_f proc3_f $30;
		set low_value_costs;

		format proc_cd proc1 proc2 proc3 $proc.;
		proc_cd_f=vvalue(proc_cd);
		proc1_f=vvalue(proc1);
		proc2_f=vvalue(proc2);
		proc3_f=vvalue(proc3);

		retain tot_cost &var._day;
		by Patid Fst_dt;
		if first.Fst_dt then do;
			tot_cost=0;
			&var._day=0;
			if &var.=1 then do;
				&var._day=1;
			end;
		end;
		if &var._day=1 then do; /*Sum up the costs of the claim with the lv proc and the claims every other proc on the same day*/
			tot_cost=sum(tot_cost,std_cost);
		end;
		if &var._day=1 then output same_day_&var.;
		if last.Fst_dt & &var._day=1 then output costs_&var.;
	run;

	/*Collapse down to the patient-year level*/
	proc sort data=costs_&var.; by Patid year; run;

	data costs_&var. (keep=Patid year cst_&var.);
		set costs_&var.;
		retain cst_&var.;
		by Patid year;
		if first.year then do;
			cst_&var.=0;
		end;
		cst_&var.=sum(cst_&var.,tot_cost);
		if last.year then output;
	run;

	proc univariate data=costs_&var.;
		var cst_&var.;
		ods output quantiles=quant_&var.;
	run;

	/*Strip formats from the CPT dataset so we can see the CPT codes*/
    proc datasets lib=work memtype=data;
    	modify same_day_&var.; 
    	attrib _all_ label=' '; 
     	attrib _all_ format=;
	run;

	proc freq data=same_day_&var.;
		tables proc_cd / out=cpt_freqs_&var.;
	run;

	/*Add on the total cost and average cost of each CPT code associated with the procedure*/
	proc sort data=same_day_&var.; by proc_cd; run;

	data proc_costs_&var. (keep=proc_cd proc_cost avg_cost);
		set same_day_&var.;
		retain proc_cost total_count;
		by proc_cd;
		if first.proc_cd then do;
			proc_cost=0;
			total_count=0;
		end;
		proc_cost=sum(proc_cost,std_cost);
		total_count=total_count+1;
		avg_cost=proc_cost/total_count;
		if last.proc_cd then output;
	run;

	/*Merge the costs and the counts of each procedure*/
	data cpt_freqs_&var;
		merge cpt_freqs_&var.
			  proc_costs_&var.;
		by proc_cd;
	run;

	data cpt_freqs_&var.;
		set cpt_freqs_&var.;
		if proc_cd~='';
		if COUNT<11 then do;
			COUNT=.;
			PERCENT=.;
			avg_cost=.;
		end;
	run;

	proc sort data=cpt_freqs_&var.; by descending proc_cost; run;
%mend;
%total_cost_all(arthro);
%total_cost_all(vertebro);
%total_cost_all(spine_inj);
%total_cost_all(renal_angio);
%total_cost_all(arthro_s);
%total_cost_all(vertebro_s);
%total_cost_all(spine_inj_s);
%total_cost_all(renal_angio_s);


/*For these procedures, sum up all costs for all procedures during the hospital stay associated with the low value procedure*/
%macro inpatient_cost(var); 

/*Create a var_day flag to group all claims that happen the same day as the low value procedure*/
proc sort data=low_value_costs; by Patid Fst_dt descending &var.; 

	data costs_&var.;
		length proc_cd_f proc1_f proc2_f proc3_f $30;
		set low_value_costs;

		retain &var._day;
		by Patid Fst_dt;
		if first.Fst_dt then do;
			&var._day=0;
			if &var.=1 & conf_id="" then do; /*Only flag days that are not inpatient stays. Inpatient stays are summed below using a different method*/
				&var._day=1;
			end;
		end;

	/*Create a var_conf flag to flag all claims that happen in the same inpatient confinement as the low value procedure*/
	proc sort data=costs_&var.; by Patid conf_id descending &var.; 

	data costs_&var. (keep=year &var._conf tot_cost std_cost Patid conf_id rename=(&var._conf=&var.))
		 same_day_&var. (keep=proc_cd proc1 proc2 proc3 std_cost);
		set costs_&var.;

		retain tot_cost &var._conf;
		by Patid conf_id;
		if first.conf_id then do;
			tot_cost=0;
			&var._conf=0;
			if &var.=1 & conf_id~="" then &var._conf=1;
		end;
		/*Sum up the costs of all claims that happen on the same day of an oupatient procedure OR during the same hospital stay as the low value procedure*/
		if &var._conf=1 | &var._day=1 then tot_cost=sum(tot_cost,std_cost);
		if &var._conf=1 then output same_day_&var.;
		if last.conf_id & (&var._conf=1 | tot_cost>0) then output costs_&var.;
	run;

	/*Collapse down to the patient-year level*/
	proc sort data=costs_&var.; by Patid year; run;

	data costs_&var. (keep=Patid year cst_&var.);
		set costs_&var.;
		retain cst_&var.;
		by Patid year;
		if first.year then do;
			cst_&var.=0;
		end;
		cst_&var.=sum(cst_&var.,tot_cost);
		if last.year then output;
	run;

	proc univariate data=costs_&var.;
		var cst_&var.;
		ods output quantiles=quant_&var.;
	run;

	/*Strip formats from the CPT dataset so we can see the CPT codes*/
    proc datasets lib=work memtype=data;
    	modify same_day_&var.; 
    	attrib _all_ label=' '; 
     	attrib _all_ format=;
	run;

	proc freq data=same_day_&var.;
		tables proc_cd / out=cpt_freqs_&var.;
	run;

	/*Add on the total cost and average cost of each CPT code associated with the procedure*/
	proc sort data=same_day_&var.; by proc_cd; run;

	data proc_costs_&var. (keep=proc_cd proc_cost avg_cost);
		set same_day_&var.;
		retain proc_cost total_count;
		by proc_cd;
		if first.proc_cd then do;
			proc_cost=0;
			total_count=0;
		end;
		proc_cost=sum(proc_cost,std_cost);
		total_count=total_count+1;
		avg_cost=proc_cost/total_count;
		if last.proc_cd then output;
	run;

	/*Merge the costs and the counts of each procedure*/
	data cpt_freqs_&var;
		merge cpt_freqs_&var.
			  proc_costs_&var.;
		by proc_cd;
	run;

	data cpt_freqs_&var.;
		set cpt_freqs_&var.;
		if proc_cd~='';
		if COUNT<11 then do;
			COUNT=.;
			PERCENT=.;
			avg_cost=.;
		end;
	run;

	proc sort data=cpt_freqs_&var.; by descending proc_cost; run;
%mend;
%inpatient_cost(carotid_end);
%inpatient_cost(carotid_end_s);
%inpatient_cost(coronary);
%inpatient_cost(coronary_s);

data dat.costs_totalled;
	merge costs_:;
	by Patid year;
run;

proc print data=dat.costs_totalled (obs=100); run;

proc univariate data=dat.costs_totalled; 
	var cst_homoc cst_coag cst_pth	cst_cardio_x cst_pft cst_cardio_stress cst_stress cst_coronary  cst_ivc
	    cst_homoc_s cst_coag_s cst_pth cst_cardio_x_s cst_pft_s cst_cardio_stress_s cst_stress_s cst_coronary_s 
		cst_ivc_s cst_arthro cst_vertebro cst_spine_inj cst_renal_angio cst_arthro_s cst_vertebro_s 
		cst_renal_angio_s cst_carotid_end cst_carotid_end_s;
run;

/************************************************************************************
PRINT CHECK
************************************************************************************/

/*Output a sample of each of the datasets to an excel workbook*/
ods tagsets.excelxp file="/sch-projects/dua-data-projects/OPTUM/rabideau/Output/calc_costs.xml" style=sansPrinter;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="arthro" frozen_headers='yes');
proc print data=quant_arthro ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="arthro_s" frozen_headers='yes');
proc print data=quant_arthro_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="vertebro" frozen_headers='yes');
proc print data=quant_vertebro ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="vertebro_s" frozen_headers='yes');
proc print data=quant_vertebro_s;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="spine_inj" frozen_headers='yes');
proc print data=quant_spine_inj ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="renal_angio" frozen_headers='yes');
proc print data=quant_renal_angio ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="renal_angio_s" frozen_headers='yes');
proc print data=quant_renal_angio_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="homoc" frozen_headers='yes');
proc print data=quant_homoc ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="homoc_s" frozen_headers='yes');
proc print data=quant_homoc_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="coag" frozen_headers='yes');
proc print data=quant_coag ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="coag_s" frozen_headers='yes');
proc print data=quant_coag_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="pth" frozen_headers='yes');
proc print data=quant_pth ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="pth_s" frozen_headers='yes');
proc print data=quant_pth_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="cardio_stress" frozen_headers='yes');
proc print data=quant_cardio_stress ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="cardio_stress_s" frozen_headers='yes');
proc print data=quant_cardio_stress_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="stress" frozen_headers='yes');
proc print data=quant_stress ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="stress_s" frozen_headers='yes');
proc print data=quant_stress_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="coronary" frozen_headers='yes');
proc print data=quant_coronary ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="coronary_s" frozen_headers='yes');
proc print data=quant_coronary_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="ivc" frozen_headers='yes');
proc print data=quant_ivc ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="ivc_s" frozen_headers='yes');
proc print data=quant_ivc_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="carotid_end" frozen_headers='yes');
proc print data=quant_carotid_end ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="carotid_end_s" frozen_headers='yes');
proc print data=quant_carotid_end_s ;
run;
ods tagsets.excelxp close;






ods tagsets.excelxp file="/sch-projects/dua-data-projects/OPTUM/rabideau/Output/same_day_cpt.xml" style=sansPrinter;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="arthro" frozen_headers='yes');
proc print data=cpt_freqs_arthro ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="arthro_s" frozen_headers='yes');
proc print data=cpt_freqs_arthro_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="vertebro" frozen_headers='yes');
proc print data=cpt_freqs_vertebro ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="vertebro_s" frozen_headers='yes');
proc print data=cpt_freqs_vertebro_s;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="spine_inj" frozen_headers='yes');
proc print data=cpt_freqs_spine_inj ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="renal_angio" frozen_headers='yes');
proc print data=cpt_freqs_renal_angio ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="renal_angio_s" frozen_headers='yes');
proc print data=cpt_freqs_renal_angio_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="homoc" frozen_headers='yes');
proc print data=cpt_freqs_homoc ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="homoc_s" frozen_headers='yes');
proc print data=cpt_freqs_homoc_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="coag" frozen_headers='yes');
proc print data=cpt_freqs_coag ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="coag_s" frozen_headers='yes');
proc print data=cpt_freqs_coag_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="pth" frozen_headers='yes');
proc print data=cpt_freqs_pth ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="pth_s" frozen_headers='yes');
proc print data=cpt_freqs_pth_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="cardio_stress" frozen_headers='yes');
proc print data=cpt_freqs_cardio_stress ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="cardio_stress_s" frozen_headers='yes');
proc print data=cpt_freqs_cardio_stress_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="stress" frozen_headers='yes');
proc print data=cpt_freqs_stress ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="stress_s" frozen_headers='yes');
proc print data=cpt_freqs_stress_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="coronary" frozen_headers='yes');
proc print data=cpt_freqs_coronary ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="coronary_s" frozen_headers='yes');
proc print data=cpt_freqs_coronary_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="ivc" frozen_headers='yes');
proc print data=cpt_freqs_ivc ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="ivc_s" frozen_headers='yes');
proc print data=cpt_freqs_ivc_s ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="carotid_end" frozen_headers='yes');
proc print data=cpt_freqs_carotid_end ;
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="carotid_end_s" frozen_headers='yes');
proc print data=cpt_freqs_carotid_end_s ;
run;
ods tagsets.excelxp close;

/*********************
CHECK END
*********************/





