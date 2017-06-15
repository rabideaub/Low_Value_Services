%include "/sch-projects/dua-data-projects/OPTUM/rabideau/Programs/gen_summary.sas";
libname fmt "/sch-projects/dua-data-projects/OPTUM/rabideau/Documentation";
libname in "/sch-projects/dua-data-projects/OPTUM/rabideau/Data";
%let cost_var = cst_lv_s; /*Specify the cost variable of interest. Total sensitive low value is cst_lv, total specific low value is cst_lv_s*/

data optum_demog (keep=Patid Fst_dt gdr_cd age age_cat product cdhp lv D_EDUCATION_LEVEL_CODE D_RACE_CODE 
					   D_HOUSEHOLD_INCOME_RANGE_CODE division rename=(cdhp=cdhp_cd));
	set in.low_value_beneficiary (where=(year=2013 & elig_2013=1));
	if 18<=age<=34 then age_cat='18-34';
	if 35<=age<=49 then age_cat='35-49';
	if 50<=age<=64 then age_cat='50-64';
	if upcase(D_EDUCATION_LEVEL_CODE)='B' then D_EDUCATION_LEVEL_CODE='A'; /*We're combining A and B into 'High School or Less'*/
	if upcase(product)='IND' then product='PPO'; /*Combine PPO and Indemnity*/
	if upcase(product)='OTH' then product='POS'; /*Combine POS and Other*/
run;

proc sort data=optum_demog; by Patid Fst_dt; run;

data optum_demog;
	length group $12;
	set optum_demog;
	retain group;
	by Patid;
	if first.Patid then group="No_Low_Value";
	if lv=1 then group="Low_Value";
	if last.Patid then output;
run;

%summary(ds=optum_demog,cutoff=100,byvar=,subset=,formats=Y);

/*Compare the total number of lv procs and costs*/
proc format;
	value $D_EDUCATION_LEVEL_CODE
	'A'=	'High School Diploma or Lower'/*'Less than 12th Grade'*/ /*We're combining A and B into 'High School or Less'*/
	/*'B'=	'High School Diploma'*/
	'C'=	'Less than Bachelor Degree'
	'D'=	'Bachelor Degree Plus'
	'U'=	'Unknown';

	value $D_HOUSEHOLD_INCOME_RANGE_CODE
	'0'=	'Unknown'
	'1'=	'<$40K'
	'2'=	'$40K-$49K'
	'3'=	'$50K-$59K'
	'4'=	'$60K-$74K'
	'5'=	'$75K-$99K'
	'6'=	'$100K+';

	value $D_RACE_CODE
	'A'=	'Asian'
	'B'=	'Black'
	'H'=	'Hispanic'
	'U'=	'Unknown'
	'W'=	'White';

	value $gdr_cd
	'M'=	'Male'
	'F'=	'Female'
	/*'U'=	'U=UNKNOWN';*/

	value $cdhp
	'1'=	'HRA'
	'2'=	'HSA'
	'3'=	'No HRA / HSA';

	value $product
	'POS'=	'Point of Service or Other' /*Combine POS and Other*/
	'EPO'=	'Exclusive Provider Organization'
	'HMO'=	'Health Maintenance Organization'
	'PPO'=	'Preferred Provider Organization or Indemnity'/*'PPO=PREFERRED PROVIDER ORGANIZATION'*/ /*Combine PPO and Indemnity*/
	/*'OTH'=	'Other'*/
	/*'IND'=	'IND=INDEMNITY'*/;
run;

%macro costs_by_demog(var);

	data low_value_beneficiary;
		set in.low_value_beneficiary;
		if 18<=age<=34 then age_cat='18-34';
		if 35<=age<=49 then age_cat='35-49';
		if 50<=age<=64 then age_cat='50-64';
		if upcase(D_EDUCATION_LEVEL_CODE)='B' then D_EDUCATION_LEVEL_CODE='A';
		if upcase(product)='IND' then product='PPO';
		if upcase(product)='OTH' then product='POS';
	run;

	proc means data=low_value_beneficiary;
		class &var.;
		var &cost_var. all_costs;
		where year=2013 & elig_2013=1;
		output out=&var. sum=;
	run;

	proc print data=&var.;
	run;

	proc sort data=&var.; by _type_; run;

	data &var.;
		length &var. $ 30;
		set &var.;
		retain all_procs_cost tot_cost;
		if _type_=0 then do;
			tot_cost=&cost_var.;
			all_procs_cost=all_costs;
		end;
		pct_cst=&cost_var./tot_cost;
		pct_all=all_costs/all_procs_cost;
		format &var. $&var..;
		&var.=vvalue(&var.);
		lv_tot_ratio=&cost_var./all_costs;
	run;

	proc print data=&var.;
		var &var.  /*&cost_var. tot_cost*/ pct_cst /*all_costs all_procs_cost*/ pct_all lv_tot_ratio;
	run;

	data &var.;
		set &var. (keep=&var. pct_cst pct_all);
		if &var.~='';
		label pct_cst = 'Percent of Low Value Spending';
		label pct_all = 'Percent of All Spending';
	run;

%mend;
%costs_by_demog(D_HOUSEHOLD_INCOME_RANGE_CODE);
%costs_by_demog(D_RACE_CODE);
%costs_by_demog(D_EDUCATION_LEVEL_CODE);
%costs_by_demog(gdr_cd);
%costs_by_demog(cdhp);
%costs_by_demog(product);
%costs_by_demog(age_cat);
%costs_by_demog(division);

proc print data=categorical; run;

proc datasets library=work kill;
run;
quit;






