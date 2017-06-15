#delimit ;
set more off;
set seed 1244329;
clear;
/******************************************************************************************************
Program: low_qual_models.do
Created by: Brendan Rabideau
Created on: 4/4/16
Purpose: To run a two part model on the Optum beneficiary level data to calculate marginal effects
		 on low value procedure costs
	  
Input: low_value_beneficiary
Output: 

Notes: 
Updates: 
******************************************************************************************************/
global depvar cst_lv_s;

use "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Data/low_value_beneficiary.dta",clear;
describe, simple;

/*Subset the data*/
keep if year==2013 & elig_2013==1 & GDR_CD~="U" & division~="UNKNOWN" & age>=18 & age<65;
*sample 100000,count;

/*Clean up dependent vars for the 2 part model*/
gen any_lv_cost=1 if ${depvar}>0 & ${depvar}!=.;
replace any_lv_cost=0 if ${depvar}==0;
tab any_lv_cost;

replace ${depvar}=0 if ${depvar}<0;
replace all_costs=0 if all_costs<0 & all_costs!=.;


gen cst_ratio=(${depvar}/all_costs)*10000 if all_costs!=0;
replace cst_ratio=0 if all_costs==0;
summarize cst_ratio,detail;

gen cst_lv_spine_inj=cst_lv_s-cst_spine_inj_s;
summarize cst_lv_s, detail;
summarize cst_back_s, detail;
summarize cst_spine_inj_s, detail;
summarize cst_lv_spine_inj, detail;


/*Formats were stripped in stat transfer - Manually apply the value labels*/
replace D_EDUCATION_LEVEL_CODE="High School Diploma or Lower" if D_EDUCATION_LEVEL_CODE=="A";
replace D_EDUCATION_LEVEL_CODE="High School Diploma or Lower" if D_EDUCATION_LEVEL_CODE=="B";
replace D_EDUCATION_LEVEL_CODE="Less than Bachelor Degree" if D_EDUCATION_LEVEL_CODE=="C";
replace D_EDUCATION_LEVEL_CODE="Bachelor Degree Plus" if D_EDUCATION_LEVEL_CODE=="D";
replace D_EDUCATION_LEVEL_CODE="Unknown" if D_EDUCATION_LEVEL_CODE=="U";

replace D_HOUSEHOLD_INCOME_RANGE_CODE="Unknown" if D_HOUSEHOLD_INCOME_RANGE_CODE=="0";
replace D_HOUSEHOLD_INCOME_RANGE_CODE="<$40K" if D_HOUSEHOLD_INCOME_RANGE_CODE=="1";
replace D_HOUSEHOLD_INCOME_RANGE_CODE="$40K-$49K" if D_HOUSEHOLD_INCOME_RANGE_CODE=="2";
replace D_HOUSEHOLD_INCOME_RANGE_CODE="$50K-$59K" if D_HOUSEHOLD_INCOME_RANGE_CODE=="3";
replace D_HOUSEHOLD_INCOME_RANGE_CODE="$60K-$74K" if D_HOUSEHOLD_INCOME_RANGE_CODE=="4";
replace D_HOUSEHOLD_INCOME_RANGE_CODE="$75K-$99K" if D_HOUSEHOLD_INCOME_RANGE_CODE=="5";
replace D_HOUSEHOLD_INCOME_RANGE_CODE="$100K+" if D_HOUSEHOLD_INCOME_RANGE_CODE=="6";

replace D_RACE_CODE="Asian" if D_RACE_CODE=="A";
replace D_RACE_CODE="Black" if D_RACE_CODE=="B";
replace D_RACE_CODE="Hispanic" if D_RACE_CODE=="H";
replace D_RACE_CODE="Unknown" if D_RACE_CODE=="U";
replace D_RACE_CODE="White" if D_RACE_CODE=="W";

replace GDR_CD="Male" if GDR_CD=="M";
replace GDR_CD="Female" if GDR_CD=="F";

replace cdhp = "HRA" if cdhp=="1";
replace cdhp = "HSA" if cdhp=="2";
replace cdhp = "No HRA / HSA" if cdhp=="3";

replace product = "Point of Service or Other" if product=="POS";
replace product = "Exclusive Provider Organization" if product=="EPO";
replace product = "Health Maintenance Organization" if product=="HMO";
replace product = "Preferred Provider Organization or Indemnity" if product=="PPO";
replace product = "Point of Service or Other" if product=="OTH";
replace product = "Preferred Provider Organization or Indemnity" if product=="IND";


gen age_cat="18-34"	if age>=18 & age<35;
replace age_cat="35-49"	if age>=35 & age<50;
replace age_cat="50-64"	if age>=50 & age<65;

replace cst_ratio=/*${impute_cst_ratio}*/0 if all_costs==0 | all_costs==.;

/*Models require numeric vars - Use encode to make the following string vars numeric*/
foreach var in D_HOUSEHOLD_INCOME_RANGE_CODE D_RACE_CODE GDR_CD cdhp product age_cat division {;
	tab `var';
	encode `var',generate(`var'2);
};


/*Park Test. The coefficient on xbetahat at the end indicates what family should be used based.*/
glm cst_ratio division2 D_HOUSEHOLD_INCOME_RANGE_CODE2 D_RACE_CODE2 GDR_CD2 product2 age_cat2 cdhp2, family(gamma)link(log);
predict xbetahat, xb;
summarize xbetahat;
gen exp_xbetahat=exp(xbetahat)*(-1);
summarize exp_xbetahat;
summarize cst_ratio;
gen test=cst_ratio+exp_xbetahat;
gen rawresid = cst_ratio + exp_xbetahat;
summarize rawresid;
gen rawvar = rawresid^2;
glm rawvar xbetahat, f(gamma)link(log);

 test xbetahat - 0 = 0; /* NLLS or Gaussian family */
 test xbetahat - 1 = 0; /* Poisson family */
 test xbetahat - 2 = 0; /* Gamma family */
 test xbetahat - 3 = 0; /* Inverse Gaussian family */

/*Park Test. The coefficient on xbetahat at the end indicates what family should be used based.*/
glm cst_lv_s division2 D_HOUSEHOLD_INCOME_RANGE_CODE2 D_RACE_CODE2 GDR_CD2 product2 age_cat2 cdhp2, family(gamma)link(log);
predict xbetahat2, xb;
summarize xbetahat2;
gen exp_xbetahat2=exp(xbetahat2)*(-1);
summarize exp_xbetahat2;
summarize cst_ratio;
gen test2=cst_ratio+exp_xbetahat;
gen rawresid2 = cst_ratio + exp_xbetahat2;
summarize rawresid2;
gen rawvar2 = rawresid2^2;
glm rawvar2 xbetahat2, f(gamma)link(log);

 test xbetahat2 - 0 = 0; /* NLLS or Gaussian family */
 test xbetahat2 - 1 = 0; /* Poisson family */
 test xbetahat2 - 2 = 0; /* Gamma family */
 test xbetahat2 - 3 = 0; /* Inverse Gaussian family */

xi: twopm cst_ratio ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 
ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(poisson) link(log));

xi: twopm cst_ratio ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 
ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));

xi: twopm cst_ratio ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 
ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gaussian) link(log));

xi: twopm cst_lv_s ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 
ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(poisson) link(log));

xi: twopm cst_lv_s ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 
ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));

xi: twopm cst_lv_s ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 
ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gaussian) link(log));









	sort D_HOUSEHOLD_INCOME_RANGE_CODE;
	by D_HOUSEHOLD_INCOME_RANGE_CODE: summarize cst_ratio,detail;
	
	sort D_RACE_CODE;
	by D_RACE_CODE: summarize cst_ratio,detail;
	
	sort D_EDUCATION_LEVEL_CODE;
	by D_EDUCATION_LEVEL_CODE: summarize cst_ratio,detail;
	
	sort GDR_CD;
	by GDR_CD: summarize cst_ratio,detail;
	
	sort cdhp;
	by cdhp: summarize cst_ratio,detail;
	
	sort product;
	by product: summarize cst_ratio,detail;
	
	sort age_cat;
	by age_cat: summarize cst_ratio,detail;
	
	sort division;
	by division: summarize cst_ratio,detail;
