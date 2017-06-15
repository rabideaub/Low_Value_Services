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
log using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Data/low_value_beneficiary.log",replace;
global depvar cst_lv_s;

use "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Data/low_value_beneficiary.dta",clear;
describe, simple;

/*Subset the data*/
keep if year==2013 & elig_2013==1 & GDR_CD~="U" & division~="UNKNOWN" & age>=18 & age<65;
*sample 10000,count;

/*Clean up dependent vars for the 2 part model*/
gen any_lv_cost=1 if ${depvar}>0 & ${depvar}!=.;
replace any_lv_cost=0 if ${depvar}==0;
tab any_lv_cost;

replace ${depvar}=0 if ${depvar}<0;
replace all_costs=0 if all_costs<0 & all_costs!=.;


gen cst_ratio=(${depvar}/all_costs)*10000 if all_costs!=0;
replace cst_ratio=0 if all_costs==0;
summarize cst_ratio,detail;

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

/*Models require numeric vars - Use encode to make the following string vars numeric*/
foreach var in D_HOUSEHOLD_INCOME_RANGE_CODE D_RACE_CODE GDR_CD cdhp product age_cat division {;
	tab `var';
	encode `var',generate(`var'2);
};

/*Get some summary stats*/	
sort D_HOUSEHOLD_INCOME_RANGE_CODE2;
by D_HOUSEHOLD_INCOME_RANGE_CODE2: summarize cst_ratio,detail;
	
sort D_RACE_CODE2;
by D_RACE_CODE2: summarize cst_ratio,detail;
	
sort GDR_CD2;
by GDR_CD2: summarize cst_ratio,detail;
	
sort cdhp2;
by cdhp2: summarize cst_ratio,detail;

sort product2;
by product2: summarize cst_ratio,detail;
	
sort age_cat2;
by age_cat2: summarize cst_ratio,detail;
	
sort division2;
by division2: summarize cst_ratio,detail;
	
	
/*Look at the distributions of components of the dependent variable. See what happens to cst_ratio as all_costs approaches 0*/
summarize ${depvar},detail;
summarize all_costs,detail;
summarize ${depvar} if ${depvar}!=0,detail;
summarize all_costs if cov_only!=1,detail;
summarize all_costs if cov_only==1,detail;
tab cov_only;

twoway lfit cst_ratio all_costs,range(1 21621.11);
graph export cost_graph.pdf,replace;

regress cst_ratio all_costs if all_costs<=21621.11 & cov_only!=1;
predict p_cst_ratio;
egen cst_lv_at_0 = mean(p_cst_ratio) if all_costs==0 & cov_only!=1; 
egen cst_lv_at_1 = mean(p_cst_ratio) if all_costs<=45 & cov_only!=1; /*1st percentile cost*/
summarize cst_lv_at_0,detail;
summarize cst_lv_at_1,detail;
global impute_cst_ratio = r(mean);
replace cst_ratio=/*${impute_cst_ratio}*/0 if all_costs==0 | all_costs==.;

egen all_cost_group = cut(all_costs) if all_costs>0 & all_costs!=., group(10) label;
egen cst_ratio_group=mean(cst_ratio), by(all_cost_group);
tab2 all_cost_group cst_ratio_group;
bysort all_cost_group : gen ok=(_n==1);
graph twoway line cst_ratio_group all_cost_group if ok==1;
graph export cost_graph1.pdf,replace;

/*Boxcox test to determine the identity link*/
boxcox cst_ratio division2 D_HOUSEHOLD_INCOME_RANGE_CODE2 D_RACE_CODE2 GDR_CD2 product2 age_cat2 cdhp2 if cst_ratio>0 & cst_ratio!=.;

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


/*Run the two part models*/
ssc install outreg;
ssc install estout;

/*Calculate Unadjusted Marginal Effects by using only 1 covariate. Can't be in a loop because each var has a difference reference specification*/
	
	/*Proportion Spending*/
	xi: twopm cst_ratio ib1.division2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store division2p, title(cst_ratio) ;

	xi: twopm cst_ratio ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store INCOME_RANGE_CODE2p, title(cst_ratio) ;
		
	xi: twopm cst_ratio ib5.D_RACE_CODE2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store D_RACE_CODE2p, title(cst_ratio) ;
	
	xi: twopm cst_ratio ib1.GDR_CD2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store GDR_CD2p, title(cst_ratio) ;
	
	xi: twopm cst_ratio ib4.product2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store product2p, title(cst_ratio) ;
	
	xi: twopm cst_ratio ib1.age_cat2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store age_cat2p, title(cst_ratio) ;
	
	xi: twopm cst_ratio ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store cdhp2p, title(cst_ratio) ;
	
	/*Total Spending*/
	xi: twopm ${depvar} ib1.division2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store division2t, title(${depvar}) ;

	xi: twopm ${depvar} ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store INCOME_RANGE_CODE2t, title(${depvar}) ;
		
	xi: twopm ${depvar} ib5.D_RACE_CODE2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store D_RACE_CODE2t, title(${depvar}) ;
	
	xi: twopm ${depvar} ib1.GDR_CD2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store GDR_CD2t, title(${depvar}) ;
	
	xi: twopm ${depvar} ib4.product2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store product2t, title(${depvar}) ;
	
	xi: twopm ${depvar} ib1.age_cat2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store age_cat2t, title(${depvar}) ;
	
	xi: twopm ${depvar} ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store cdhp2t, title(${depvar}) ;

/*Unadjusted Marginal Effects for the cost ratio model*/
esttab division2p INCOME_RANGE_CODE2p D_RACE_CODE2p GDR_CD2p product2p age_cat2p cdhp2p 
	using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Output/me_prop_unadj.xls", 
	cells((margins_b(star fmt(4)) p(fmt(%4.3f)) ci_l(fmt(a3)) ci_u(fmt(a3))) margins_se(par(`"("' `")"') fmt(4))) /*These are parentheses that excel can see. otherwise you can just specify par*/
	legend label varlabels(_cons Constant) mtitles nodepvars
	extracols(5)
	stats(N, fmt(0 3) labels(`"Observations"')) replace;
	
/*Unadjusted Marginal Effects for the total cost model*/
esttab division2t INCOME_RANGE_CODE2t D_RACE_CODE2t GDR_CD2t product2t age_cat2t cdhp2t
	using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Output/me_tot_unadj.xls", 
	cells((margins_b(star fmt(4)) p(fmt(%4.3f)) ci_l(fmt(a3)) ci_u(fmt(a3))) margins_se(par(`"("' `")"') fmt(4))) /*These are parentheses that excel can see. otherwise you can just specify par*/
	legend label varlabels(_cons Constant) mtitles nodepvars
	extracols(5)
	stats(N, fmt(0 3) labels(`"Observations"')) replace;
	
	
/*Adjusted Mean Marginal Effects*/
xi: twopm cst_ratio ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));
estadd margins, dydx(*) post;
estimates store all_prop, title(cst_ratio);

xi: twopm ${depvar} ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));
estadd margins, dydx(*) post;
estimates store all_tot, title(cst_lv_s);

if 0==1 {;
	foreach var in cardio musculo neuro diagnostic preoperative {;
		gen cst_tot_`var'=cst_lv_s-cst_`var'_s;
		gen cst_ratio_`var'=((cst_lv_s-cst_`var'_s)/all_costs)*10000 if all_costs!=0 & all_costs!=.;
		replace cst_ratio_`var'=0 if all_costs==0 | all_costs==.;
		
		xi: twopm cst_tot_`var' ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));
		estadd margins, dydx(*) post;
		estimates store `var'_tot, title(`var');

		xi: twopm cst_ratio_`var' ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));
		estadd margins, dydx(*) post;
		estimates store `var'_prop, title(`var');
	};
};

/*Run a model for costs removing one of the five most expensive procedures*/
foreach proc in spine_inj_s scan_head_s back_s coronary_s carotid_scan_asymp_s hpv_s ct_sinus_s t3_test_s stress_s arthro_s {;
	replace cst_`proc'=0 if cst_`proc'==.;
	gen cst_lv_`proc' = ${depvar}-cst_`proc';
	gen cst_ratio_`proc' = (cst_lv_`proc'/all_costs)*10000 if all_costs!=0 & all_costs!=.;
	replace cst_ratio_`proc' = 0 if all_costs==0 | all_costs==.;

	xi: twopm cst_lv_`proc' ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store `proc'_tot, title(cst_ratio);

	xi: twopm cst_ratio_`proc' ib1.division2 ib1.D_HOUSEHOLD_INCOME_RANGE_CODE2 ib5.D_RACE_CODE2 ib1.GDR_CD2 ib4.product2 ib1.age_cat2 ib3.cdhp2, first(probit) second(glm,family(gamma) link(log));
	estadd margins, dydx(*) post;
	estimates store `proc'_prop, title(cst_ratio);
	
	/*Each model minus one of the most expensive procedures. Depvar = proportion low value spending to total spending*/
	esttab `proc'_tot `proc'_prop using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Output/me_`proc'.xls", 
	cells((margins_b(star fmt(4)) p(fmt(%4.3f)) ci_l(fmt(a3)) ci_u(fmt(a3))) margins_se(par(`"("' `")"') fmt(4))) /*These are parentheses that excel can see. otherwise you can just specify par*/
	legend label varlabels(_cons Constant) mtitles("Total Costs" "Proportional Costs") nodepvars
	extracols(5)
	stats(N, fmt(0 3) labels(`"Observations"')) replace;
};

	/*Each model minus one of the most expensive procedures. Depvar = proportion low value spending to total spending*/
	esttab all_tot all_prop using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Output/me_all.xls", 
	cells((margins_b(star fmt(4)) p(fmt(%4.3f)) ci_l(fmt(a3)) ci_u(fmt(a3))) margins_se(par(`"("' `")"') fmt(4))) /*These are parentheses that excel can see. otherwise you can just specify par*/
	legend label varlabels(_cons Constant) mtitles("Total Costs" "Proportional Costs") nodepvars
	extracols(5)
	stats(N, fmt(0 3) labels(`"Observations"')) replace;

if 0==1 {;
/*Each model has a different depvar. Each depvar corresponds to a procedure grouping*/
esttab all_prop cardio_prop musculo_prop neuro_prop diagnostic_prop preoperative_prop using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Output/me_prop_group.xls", 
	cells((margins_b(star fmt(4)) p(fmt(%4.3f)) ci_l(fmt(a3)) ci_u(fmt(a3))) margins_se(par(`"("' `")"') fmt(4))) /*These are parentheses that excel can see. otherwise you can just specify par*/
	legend label varlabels(_cons Constant) mtitles("All Costs" "No Cardio Costs" "No Musculoskeletal Costs" "No Neurological Costs" "No Diagnostic Costs" "No Preoperative Costs")
	extracols(5)
	stats(N, fmt(0 3) labels(`"Observations"')) replace;
	
esttab all_tot cardio_tot musculo_tot neuro_tot diagnostic_tot preoperative_tot using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Output/me_tot_group.xls", 
	cells((margins_b(star fmt(4)) p(fmt(%4.3f)) ci_l(fmt(a3)) ci_u(fmt(a3))) margins_se(par(`"("' `")"') fmt(4))) /*These are parentheses that excel can see. otherwise you can just specify par*/
	legend label varlabels(_cons Constant) mtitles("All Costs" "No Cardio Costs" "No Musculoskeletal Costs" "No Neurological Costs" "No Diagnostic Costs" "No Preoperative Costs")
	extracols(5)
	stats(N, fmt(0 3) labels(`"Observations"')) replace;
};
	
/*Each model minus one of the most expensive procedures. Depvar = proportion low value spending to total spending*/
esttab all_prop spine_inj_s_prop scan_head_s_prop back_s_prop coronary_s_prop carotid_scan_asymp_s_prop 
		hpv_s_prop ct_sinus_s_prop t3_test_s_prop stress_s_prop arthro_s_prop /*coronary_s_prop carotid_end_s_prop*/ 
		using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Output/me_prop_proc.xls", 
	cells((margins_b(star fmt(4)) p(fmt(%4.3f)) ci_l(fmt(a3)) ci_u(fmt(a3))) margins_se(par(`"("' `")"') fmt(4))) /*These are parentheses that excel can see. otherwise you can just specify par*/
	legend label varlabels(_cons Constant) mtitles("All Costs" "No Spinal Injections" "No Head Scans" "No Back Scans" "No Stress CAD" 
		"No Carotid Scan Asymp" "No HPV" "No CT Scan for Sinusitis" "No T3 Testing" "No Stress Testing" "No Arthroscopy") nodepvars
	extracols(5)
	stats(N, fmt(0 3) labels(`"Observations"')) replace;
	
/*Each model minus one of the most expensive procedures. Depvar = total low value spending*/
esttab all_tot spine_inj_s_tot scan_head_s_tot back_s_tot coronary_s_tot carotid_scan_asymp_s_tot hpv_s_tot 
		ct_sinus_s_tot t3_test_s_tot stress_s_tot arthro_s_tot 
		using "/schaeffer-a/sch-projects/dua-data-projects/OPTUM/rabideau/Output/me_tot_proc.xls", 
	cells((margins_b(star fmt(4)) p(fmt(%4.3f)) ci_l(fmt(a3)) ci_u(fmt(a3))) margins_se(par(`"("' `")"') fmt(4))) /*These are parentheses that excel can see. otherwise you can just specify par*/
	legend label varlabels(_cons Constant) mtitles("All Costs" "No Spinal Injections" "No Head Scans" "No Back Scans" "No Stress CAD" 
		"No Carotid Scan Asymp" "No HPV" "No CT Scan for Sinusitis" "No T3 Testing" "No Stress Testing" "No Arthroscopy") nodepvars
	extracols(5)
	stats(N, fmt(0 3) labels(`"Observations"')) replace;
	

	
	
	
	
/*	Sample esttab formatted output from http://www.jwe.cc/2012/03/stata-latex-tables-estout/

	esttab A B C using table4.tex, replace f
	label booktabs b(3) p(3) eqlabels(none) alignment(S S) collabels("\multicolumn{1}{c}{$\beta$ / SE}" "\multicolumn{1}{c}{Mfx}") 
	drop(_cons spouse*  ) 
	star(* 0.10 ** 0.05 *** 0.01) 
	cells("b(fmt(3)star) margins_b(star)" "se(fmt(3)par)") 
	refcat(age18 "\emph{Age}" male "\emph{Demographics}" educationage "\emph{Education}" employeddummy "\emph{Employment}" oowner "\emph{Housing}" hhincome_thou "\emph{Household Finances}" reduntant "\emph{Income and Expenditure Risk}" literacyscore "\emph{Behavioural Characteristics}", nolabel) ///
	stats(N, fmt(0 3) labels(`"Observations"'))
 */  




