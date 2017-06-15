/*******************************************************************************************
********************************************************************************************
Program: low_qual_build
Project: Physician Value Index (Sood)
By: Brendan Rabideau
Created on: 6/1/15
Updated on: 1/12/16
Purpose: Create value measures based on the prevalence of 'low-value procedures'.

Input: OPTUM Medical Claims Data
Output: out.low_value_build.sas7bdat

Notes: (1) The original paper this is based on used Medicare info which does not perfectly
		   overlap with OPTUM data. This leads to slight variation
	   (2) CCW indicates that for some conditions 2 DX must be present within x-amount
		   of time if it is a certain treatment type (HHA, IRF, etc). The OPTUM data is very detailed
		   (over 3000 provider types) so these treatment types were clustered into prov_cat = FACILITY, 
		   PROFESSIONAL, and MISCELLANEOUS. Facility requires only 1 DX, PROFESSIONAL and MISCELLANEOUS 
		   require 2. Revisit?
	   (3) This program identifies patients with certain time-sensitive condtions which will be
		   used in the next program (low_qual_procs.sas) in conjunction with particular procedure
		   codes to flag instances of low-value procedure.

Updates:
	   6/15/15: Updated comments to improve documentations
	   7/20/15: Updated Surgery Indicators - previously missing retained surgery dates
	   8/17/15: Incorporated BETOS codes
	   8/17/15: Added dialysis flag. If a patient receives dialysis once, they are marked as receiving dialysis
				for every claiming going forward. No timeframe specified by CCW.
	   8/17/15: Modified to work with OPTUM datasets from Ingenix datasets. Biggest difference is provider category,
				see note 2 above.
	   8/21/15: Merged on member details dataset to get age and gender (equivalent dataset in Ingenix is eligibility).
	   9/03/15: Dropping patients who are in facilities - Our primary interest is private physicians. Facility
				patient stays are still used to detect chronic conditions before being dropped
	   10/19/15: Drop everyone 65+ and keep inpatient facilities for the time being. 
	   12/01/15: Added indicators for the conditions involved in identifying the specific versions of the low value procedures 
	   12/15/15: Switched the SES dataset instead of DoD. Added some eligibility vars
	   01/11/16: Flattened eligibility file and kept eligible benes without med claims in a given year
	   04/12/16: Changed IHD and AMI flags to exclude claims within 6months of the original detection

*********************************************************************************************
********************************************************************************************/

/***************************************
****************************************
MACRO SET
****************************************
***************************************/
options compress=yes mprint;

%let out = /sch-projects/dua-data-projects/OPTUM/rabideau/Data;
libname raw "/sch-data-library/dua-data/OPTUM/Original_data/Data";
libname med  "/sch-projects/dua-data-projects/OPTUM/rabideau/Data";
libname out "&out.";


/***************************************
****************************************
DATA BUILD
****************************************
***************************************/

/*Read in the relevant OPTUM datasets*/
data med;
	set out.ses_m2011_2013;
	if prov in('000000000','0','') | patid in('000000000','0','') then delete; 
	year=year(Fst_dt);
run;

/*Capture all eligible beneficiaries for each year - even those without claims*/

/*Benes have multiple observations for different enrollment periods. Dynamically flatten with arrays by patid*/
data elig;
	set raw.ses_mbr;
	if patid ~in('000000000','0','');
	retain num;
	by patid;
	if first.patid then num=0;
	num+1;
run;

proc print data=elig (obs=20);
run;

proc freq data=elig;
	tables num / out=count_ds;
run;

proc print data=count_ds;
run;

/*Store the maximum number of obs a single bene has*/
data _null_;
	set count_ds end=last;
	if last then call symput('N',trim(left(num)));
run;

%put &N.;

/*Make an eligibility start and end date for each period of enrollment that a bene has*/
data elig_array;
	set elig;
	retain eligeff1-eligeff&N. eligend1-eligend&N.;
	array eligb {&N.} eligeff1-eligeff&N.;
	array elige {&N.} eligend1-eligend&N.;
	by patid;
	if first.patid then do;
		do i=1 to &N.;
			eligb[i]=.;
			elige[i]=.;
		end;
	end;

	/*do j=1 to &N.;
		if num=i then do;*/ 
			eligb[num]=eligeff;
			elige[num]=eligend;
		/*end;
	end;*/
	drop i /*j*/;
	if last.patid then output;
	format eligeff: eligend: MMDDYY8.;
run;

proc print data=elig_array (obs=20);
	where num>1;
run;

/*Make yearly eligibility files for if a bene was fully are partially enrolled in a given year.
  Continuous full-year enrollment flags will be added later. For now partial years are fine*/
data elig_2011 elig_2012 elig_2013;
	set elig_array (keep=patid gdr_cd yrdob product cdhp division eligeff: eligend:);
	%macro eligibility;
		%do year=2011 %to 2013;
			%do i=1 %to &N.;
				if year(eligeff&i.)=&year. | year(eligend&i.)=&year. | (year(eligeff&i.)<&year. & year(eligend&i.)>&year.) then do;
					year=&year.;
					output elig_&year.;
				end;
			%end;
		%end;
	%mend;
	%eligibility;
run;

proc sort data=elig_2011 nodupkey; by patid year; run;
proc sort data=elig_2012 nodupkey; by patid year; run;
proc sort data=elig_2013 nodupkey; by patid year; run;

data elig_2013_test;
	set elig_2013;
		%macro elig;
		%do i=2013 %to 2013;
			elig_&i.=0;
			%do j=1 %to &N.;
				if eligeff&j.<=mdy(1,1,&i.) & eligend&j.>=mdy(12,31,&i.) then elig_&i.=1;
			%end;
		%end;
	%mend;
	%elig;
	counter=1;
run;

proc freq data=elig_2013_test;
	tables counter elig_2013;
run;

title "ELIGIBILITY 2011";
proc print data=elig_2011 (obs=20);
run;
title "ELIGIBILITY 2012";
proc print data=elig_2012 (obs=20);
run;
title;

/*Read in the SES variables*/
data ses;
	set raw.ses_ses;
run;

proc sort data=med; by Patid year; run;
proc sort data=ses nodupkey; by Patid; run;

/*Merge medical claims with eligibility information. Keep all that were eligible in a given year, even if no claim exists*/
proc print data=med (obs=10);
	var patid year;
	where year=2013;
run;
proc print data=elig_2013(obs=10);
	var patid year;
run;
proc contents data=med;run;
proc contents data=elig_2013; run;

data elig;
	set elig_2011
		elig_2012
		elig_2013;
run;

proc sort data=elig; by Patid year; run;

data med;
	merge med(in=a)
		  elig(in=b);
	by Patid year;
	age=year-yrdob;
	if a & b then match=1;
	else match=0;
	if b then keep_obs=1;
	if ~a then cov_only=1;
	%macro elig;
		%do i=2013 %to 2013;
			elig_&i.=0;
			%do j=1 %to &N.;
				if eligeff&j.<=mdy(1,1,&i.) & eligend&j.>=mdy(12,31,&i.) then elig_&i.=1;
			%end;
		%end;
	%mend;
	%elig;
	if 18<=age<65 | cov_only=1 then age_good=1;
run;

proc freq data=med;
	tables age_good keep_obs match*year elig_2013*year cov_only*year;
run;

title "ELIGIBILITY PLUS MED CLAIMS";
proc print data=med (obs=50);run;
title; 

data med;
	merge med (in=a)
		  ses (in=b);
	by Patid;
run;

/*Some conditions are identified with BETOS codes - use a xwalk to convert HCPCS to BETOS*/
data betos; 
  infile '/sch-projects/dua-data-projects/OPTUM/rabideau/Documentation/BETOS_HCPCS_xwalk.txt'; 
  input START $ LABEL $; 
run;
data betos;
	set betos;
	FMTNAME="$BETOS";
run;
proc sort data=betos nodupkey; by START; run;
proc format cntlin=betos;
run;

/*Cluster provider category (provcat) to identify which claims need 2 DXs and which claims only need 1*/
data provcat; 
  *length LABEL $20;
  infile "/sch-projects/dua-data-projects/OPTUM/rabideau/Documentation/optum_provcat.txt" DELIMITER=','; 
  input START $ DESCRIPTION $ CATGY_ROL_UP_1_DESC $ CATGY_ROL_UP_2_DESC $CATGY_ROL_UP_3_DESC $ LABEL $; 
run;

proc print data=provcat (obs=10); run;
proc contents data=provcat; run;

data provcat (keep=START LABEL FMTNAME);
	set provcat;
	FMTNAME="$PROVCAT";
	START=compress(START);
	LABEL=compress(LABEL);
run;
proc sort data=provcat nodupkey; by START; run;
proc format cntlin=provcat;
run;

/*Create BETOS and PROV_CAT vars, and remove leading and trailing blanks from key variables*/
data med;
	length prov_cat $ 20;
	set med;
	betos=compress(put(proc_cd,$BETOS.));
	betos1=compress(put(proc1,$BETOS.));
	betos2=compress(put(proc2,$BETOS.));
	betos3=compress(put(proc3,$BETOS.));
	diag1=compress(diag1);
	diag2=compress(diag2);
	diag3=compress(diag3);
	diag4=compress(diag4);
	diag5=compress(diag5);
	proc_cd=compress(proc_cd);
	proc1=compress(proc1);
	proc2=compress(proc2);
	proc3=compress(proc3);
	prov_cat=compress(put(compress(provcat),$PROVCAT.));

	/*Clean some key variables*/
	if D_HOUSEHOLD_INCOME_RANGE_CODE='' then D_HOUSEHOLD_INCOME_RANGE_CODE='0';
	if D_RACE_CODE='' then D_RACE_CODE='U';
	if D_EDUCATION_LEVEL_CODE='' then D_EDUCATION_LEVEL_CODE='U';
run;

/*Generate contents for the relevant dataset*/
proc contents data=med out=med_cont (keep=NAME TYPE LENGTH VARNUM LABEL FORMAT); run;

/*********************
PRINT CHECK
*********************/
/*Output a sample of each of the datasets to an excel workbook*/
ods tagsets.excelxp file="&out./low_value.xml" style=sansPrinter;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="Medical" frozen_headers='yes');
proc print data=med (obs=1000);
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="Med Contents" frozen_headers='yes');
proc print data=med_cont;
run;
ods tagsets.excelxp close;
/*********************
CHECK END
*********************/

proc freq data=med;
	tables prov_cat;
run;

proc sort data=med; by Patid Fst_Dt; run;

data med;
	set med (where=(18<=age<65 | cov_only=1));
	by patid;
	/*Retain markers for conditions that are time dependent (e.g. flag if bone density test was performed at least
	  once in the last two years)*/

	array dx [5] diag1-diag5;

	/*Chronic Kidney Disease, Bone Density Testing, Deep Vein Thrombosis-Pulmonary Embolism,
	  Non-Cardiothoracic Surgery, Surgery, Stroke-Transient Ischemic Attack, Ischemic Heart Disease*/
	retain CKD CKD_dx CKD_dx_dt CKD_dt 
		   prebone bone_dx_dt 
		   dvt_pe dvt_pe_dt 
		   rec_dvt_pe rec_dvt_pe_dt 
		   stroke_tia stroke_tia_dx stroke_tia_dx_dt stroke_tia_dt 
		   ihd ihd_dt first_ihd_dt ihd_all
		   dialysis
		   ost ost_dt
		   b12_folate
		   hyp_cal
		   sinusitis
		   sinusitis_dt
		   bp_dt
		   ami ami_dt first_ami_dt ami_all
		   epilepsy
		   arth arth_dx arth_dx_dt arth_dt
		   thyroid thyroid_dt
		   prepap pap_dx_dt 
		   precyst cyst_dx_dt
		   radiography radiography_dt
		   ed14 ed14_dt;


	if first.patid then do;
		CKD_dx_dt = .;
		CKD_dt = .;
		CKD_dx = 0;
		CKD = 0; /*Indicates confirmed CKD within last 2yrs*/

		bone_dx_dt = .;
		prebone = 0; /*Indicates a claim occurred within 2yrs of a previous bone density exam*/

		dvt_pe_dt = .;
		dvt_pe = 0; /*Indicates confirmed deep vein throm or pulm emb within last 30days*/

		rec_dvt_pe_dt = .;
		rec_dvt_pe = 0; /*Indicates recent deep vein throm or pulm emb within last 30days and prior dvt_pe >90days prior */

		stroke_tia_dx_dt = .;
		stroke_tia_dt = .;
		stroke_tia_dx = 0;
		stroke_tia = 0; /*Indicates confirmed stroke_tia within last 1yr*/

		ihd_dt = .;
		first_ihd_dt = .;
		ihd_all=0;
		ihd = 0; /*Indicates confirmed IHD between 3 months and 1yr*/

		dialysis = 0; /*Indicates a patient is undergoing dialysis - no timeframe mentioned on CCW*/

		ost = 0; /*Indicates Osteoporosis diagnosis within the last 1yr*/
		ost_dt = .; 

		b12_folate=0; /*Indicates a B12 or folate deficiency at any point in the pasat*/
		
		hyp_cal = 0; /*Indicates hypercalcemia in a 2009 claim only*/
		
		sinusitis=0; /*Indicates chronic sinusitits - a sinusitis diagnosis occurring between 30 days and 1 year before the claim*/
		sinusitis_dt=.;

		bp_dt=.; /*First observable date of back pain diagnosis*/

		ami=0; /*Indicates AMI between 3months and 1yr*/
		ami_all=0;
		first_ami_dt=.;
		ami_dt=.;

		epilepsy=0; /*Indicates epilepsy or convulsions at any point in the past*/

		arth_dx_dt = .;
		arth_dt = .;
		arth_dx = 0;
		arth = 0; /*Indicates confirmed arthritis within last 2yrs*/

		thyroid_dt=.;
		thyroid=0; /*Indicates hypothyroidism within the same year as the claim*/

		pap_dx_dt = .;
		prepap = 0; /*Indicates a claim occurred within 30months of a previous pap procedure*/

		cyst_dx_dt = .;
		precyst = 0; /*Indicates a claim occurred within 60 days of a previous adnexal cyst imaging*/

		radiography_dt=.;
		radiography=0; /*Indicates radiography within 7 days*/

		ed14_dt=.;
		ed14=0; /*Indicates ED visit within 14 days of claim*/
	end;


	do i=1 to dim(dx);
	/*CKD Diag*/
		if CKD_dt=. | (Fst_Dt - CKD_dt > (365.25)) then CKD = 0; /*If >1yr since confirmed CKD, reset flag to 0*/
		if CKD_dx_dt=. | (Fst_Dt-CKD_dx_dt>=(365.25)) then CKD_dx = 0; /*If >1yr since CKD dx, reset dx counter 0*/

		if dx[i] in('01600', '01601','01602','01603','01604','01605','01606','0954', '1890', '1899',
					 '2230', '23691','24940','24941','25040','25041','25042','25043','2714', '27410','587',
					 '28311','40301','40311','40391','40402','40403','40412','40413','40492','40493','586',
					 '4401', '4421', '5724', '5800', '5804', '58081','58089','5809', '5810', '5811', '5812',
					 '5813', '58181','58189','5819', '5820', '5821', '5822', '5824', '58281','58289','5829',
					 '5830', '5831', '5832', '5834', '5836', '5837', '58381','58389','5839', '5845', '5846',
					 '5847', '5848', '5849', '585',  '5851', '5852', '5853', '5854', '5855', '5856', '5859', 
					 '5880', '5881', '58881','58889','5889', '591',  '75312','75313','75314','75315','75316',
					 '75317','75319','75320','75321','75322','75323','75329','7944') then do;
			/*If one of these types CKD is confirmed. If not, 2 dx within 2yr are required*/
			if  trim(left(prov_cat)) in("FACILITY") then do; 
				CKD = 1;
				CKD_dt = Fst_Dt;
			end;
			else if trim(left(prov_cat)) in("PROFESSI","MISCELLA") then do;
				CKD_dx +1;
				CKD_dx_dt = Fst_Dt;
			end;
		end;
		if CKD_dx >=2 then do; /*If dx counter >=2 within 1yr, CKD is confirmed*/
			CKD = 1;
			CKD_dt = Fst_Dt;
		end;

	/*Bone Density Testing*/
		if i=1 then do; /*Bone test is proc based, not diag based, so do not loop it like the conditions*/
			if bone_dx_dt=. | (Fst_Dt-bone_dx_dt>(365.25*2)) then prebone=0; 
			if proc_cd in('76977','77078','77079','77080','77083','78350','78351') | 
			   proc1   in('76977','77078','77079','77080','77083','78350','78351') |
			   proc2   in('76977','77078','77079','77080','77083','78350','78351') |
			   proc3   in('76977','77078','77079','77080','77083','78350','78351') then do;
			   prebone+1;
			   bone_dx_dt=Fst_Dt;
			end;
		end;

	/*DVT-PE*/
		if Fst_Dt-dvt_pe_dt>30 | dvt_pe_dt=. then dvt_pe=0; /*if 30 days since DVT_PE dx, reset flag to 0*/
		if dx[i] in('4151', '4510', '45111', '45119', '4512', '45181', '4519', '4534', 'V1251') then do;
			dvt_pe=1;
			if dvt_pe_dt=. then rec_dvt_pe_dt=Fst_Dt; /*First diagnosis of DVT_PE only*/
			dvt_pe_dt=Fst_Dt;
		end;

		/*if 90 days after original DVT_PE dx AND there is another DVT_PE diagnosis within 30 days, set recurrent thrombosis flag = 1*/
		if Fst_Dt-rec_dvt_pe_dt>90 & rec_dvt_pe_dt~=. & dvt_pe=1 then rec_dvt_pe=1; 
			
	/*Stroke-TIA*/
		do j = 1 to dim(dx);
			/*Exclusionary criteria. If these conditions are met do not count this obs towards the Stroke_TIA indicator,
			  however if there is a history of Stroke_TIA within a year that is still retained*/
			if substr(dx[j],1,3) in('800','801','802','803','804','850','851','852','853','854') |
			   substr(diag1,1,3) in('V57') then skip_step=1; 
		end;

		/*If >1yr since confirmed stroke_TIA, reset flag to 0*/
		if stroke_TIA_dt=. | (Fst_Dt - stroke_TIA_dt > (365.25)) then stroke_TIA = 0; 
		/*If >1yr since stroke_TIA dx, reset dx counter to 0*/
		if stroke_TIA_dx_dt=. | (Fst_Dt-stroke_TIA_dx_dt>=(365.25)) then stroke_TIA_dx = 0;

		if skip_step~=1 then do; /*Skip this step if exclusionary criteria are present*/
			if dx[i] in('430',  '431',  '43301', '43311', '43321','43331','43381','43391','43400','43401',
		     		    '43410','43411','43490', '43491', '4350', '4351', '4353', '4358', '4359', '436',  '99702') then do;
				if  trim(left(prov_cat)) in("FACILITY") then do; /*If inpatient and dx then confirmed stroke_TIA*/
					stroke_TIA = 1;
					stroke_TIA_dt = Fst_Dt;
				end;
				else if trim(left(prov_cat)) in("PROFESSI","MISCELLA") then do;
					stroke_TIA_dx +1;
					stroke_TIA_dx_dt = Fst_Dt;
				end;
			end;
			if stroke_TIA_dx >=2 then do; /*If 2 dx within 1yr, confirmed stroke_TIA*/
				stroke_TIA = 1;
				stroke_TIA_dt = Fst_Dt;
			end;
		end;

		/*Ischemic Heart Disease between 3 months and 1 year*/
		if IHD_dt=. | (Fst_Dt - IHD_dt > (365.25)) then IHD = 0; /*If >1yr since confirmed IHD, reset flag to 0*/

		if dx[i] in('41000', '41001', '41002', '41010', '41011', '41012', '41020', '41021', '41022', '41401',
					'41030', '41031', '41032', '41040', '41041', '41042', '41050', '41051', '41052', '41060',	
					'41061', '41062', '41070', '41071', '41072', '41080', '41081', '41082', '41090', '41091',	
					'41092', '4110',  '4111',  '41181', '41189', '412',   '4130',  '4131',  '4139',  '41400', 
					'41402', '41403', '41404', '41405', '41406', '41407', '41412', '4142',  '4143',  '4144',	
				    '4148',  '4149'	) & trim(left(prov_cat)) in("PROFESSI","MISCELLA","FACILITY") then do;
			if IHD_dt=. then first_ihd_dt=Fst_Dt;
			IHD = 1;
			IHD_all=1;
			IHD_dt = Fst_Dt;
		end;

		if IHD=1 & 0<=Fst_Dt-first_ihd_dt<=(30.4*3) then IHD=0; /*If it is within 3 months of the first IHD detection, set to 0*/

		/*Dialysis*/
		if betos in('P9A','P9B') | betos1 in('P9A','P9B') | betos2 in('P9A','P9B') | betos3 in('P9A','P9B')
		then dialysis=1;

		/*Osteoporosis Diag*/
		if ost_dt=. | (Fst_Dt - ost_dt > (365.25)) then ost = 0; /*If >1yr since confirmed ost, reset flag to 0*/

		if dx[i] in('73300', '73301', '73302', '73303', '73309') then do;
			/*If one of these types, ost is confirmed*/
			if  trim(left(prov_cat)) in("FACILITY","PROFESSI","MISCELLA") then do; 
				ost = 1;
				ost_dt = Fst_Dt;
			end;
		end;

		/*B12 or Folate disorders*/
		if dx[i] in('2662','2704','2810','2811','2812','2859') then b12_folate=1;

		/*Hypercalcemia Diagnosis in 2009*/
		if dx[i] in('2754') & year=2009 then hyp_cal=1;

		/*Chronic Sinusitis (last diagnosis between 30 days and 1 year ago)*/
		if sinusitis_dt=. | (Fst_Dt - sinusitis_dt > 365.25 | Fst_Dt - sinusitis_dt < 30 ) then sinusitis = 0;
		else if 30 <= Fst_Dt - sinusitis_dt <= 365.25 then sinusitis = 1;

		if substr(dx[i],1,3) in('461','473') then do;
			sinusitis_dt = Fst_Dt;
		end;

		/*First diagnosis of back pain indicator*/
		if bp_dt = . & dx[i] in('7213','72190','72210','72252','7226','72293','72402','7242',
								'7243','7244','7245','7246','72470','72471','72479','7385',
								'7393','7394','8460','8461','8462','8463','8468','8469','8472') then bp_dt=Fst_dt;
		
		/*AMI between 3 months and 1 year in an inpatient setting*/
		if ami_dt=. | (Fst_Dt - ami_dt > (365.25)) then ami = 0; /*If >1yr since confirmed ami, reset flag to 0*/

		if dx[1] in('41001', '41011', '41021', '41031', '41041', '41051', '41061', '41071', '41081', '41091') | /*Only the 1st and 2nd DX count*/
		   dx[2] in('41001', '41011', '41021', '41031', '41041', '41051', '41061', '41071', '41081', '41091') then do;
			if  trim(left(prov_cat)) in("FACILITY") then do; /*Only an Inpatient setting counts*/
				if ami_dt=. then first_ami_dt=Fst_Dt;
				ami = 1;
				ami_all=1;
				ami_dt = Fst_Dt;
			end;
		end;
		if ami=1 & 0<=Fst_Dt-first_ami_dt<=(30.4*3) then ami=0; /*If it is within 3 months of the first AMI detection, set to 0*/

		/*Epilepsy or Convulsions*/
		if substr(dx[i],1,3) in('345') | substr(dx[i],1,4) in('7803','7810') then epilepsy=1;

		/*Arthritis*/
		if arth_dt=. | (Fst_Dt - arth_dt > (365.25)) then arth = 0; /*If >1yr since confirmed arth, reset flag to 0*/
		if arth_dx_dt=. | (Fst_Dt-arth_dx_dt>=(365.25)) then arth_dx = 0; /*If >1yr since arth dx, reset dx counter 0*/

		if dx[i] in('7140','7141','7142','71430','71431','71432','71433','71500','71504','71509','71510',
					'71511','71512','71513','71514','71515','71516','71517','71518','71520','71521','71522',
					'71523','71524','71525','71526','71527','71528','71530','71531','71532','71533','71534',
					'71535','71536','71537','71538','71580','71589','71590','71598') then do;
			if trim(left(prov_cat)) in("FACILITY","PROFESSI","MISCELLA") then do;
				arth_dx +1;
				arth_dx_dt = Fst_Dt;
			end;
		end;
		if arth_dx >=2 then do; /*If dx counter >=2 within 2yr, arth is confirmed*/
			arth = 1;
			arth_dt = Fst_Dt;
		end;

	/*Hypothyroidism*/
		if thyroid_dt=. | (Fst_Dt - thyroid_dt > (365.25)) then thyroid = 0; /*If >1yr since confirmed hypothyroidism, reset flag to 0*/

		if substr(dx[i],1,3) in('244') then do;
			thyroid = 1;
			thyroid_dt = Fst_Dt;
		end;

	/*Annual Pap Testing*/
		if i=1 then do; /*pap test is proc based, not diag based, so do not loop it like the conditions*/
			if pap_dx_dt=. | (Fst_Dt-pap_dx_dt>(30.4*30)) then prepap=0; /*Within 30 months*/
			if proc_cd in('88141', '88142', '88143', '88147', '88148', '88150', '88152', '88153', '88154', 
					      '88164', '88165', '88166', '88167', '88174', '88175', 'G0123', 'G0124', 'G0141', 
					      'G0143', 'G0144', 'G0145', 'G0147', 'G0148', 'P3000', 'Q0091') | 
			   proc1   in('88141', '88142', '88143', '88147', '88148', '88150', '88152', '88153', '88154', 
					      '88164', '88165', '88166', '88167', '88174', '88175', 'G0123', 'G0124', 'G0141', 
					      'G0143', 'G0144', 'G0145', 'G0147', 'G0148', 'P3000', 'Q0091') | 
			   proc2   in('88141', '88142', '88143', '88147', '88148', '88150', '88152', '88153', '88154', 
					      '88164', '88165', '88166', '88167', '88174', '88175', 'G0123', 'G0124', 'G0141', 
					      'G0143', 'G0144', 'G0145', 'G0147', 'G0148', 'P3000', 'Q0091') | 
			   proc3   in('88141', '88142', '88143', '88147', '88148', '88150', '88152', '88153', '88154', 
					      '88164', '88165', '88166', '88167', '88174', '88175', 'G0123', 'G0124', 'G0141', 
					      'G0143', 'G0144', 'G0145', 'G0147', 'G0148', 'P3000', 'Q0091') then do;
			   prepap+1;
			   pap_dx_dt=Fst_Dt;
			end;
		end;

	/*Annual cyst Testing*/
		if i=1 then do; /*cyst test is proc based, not diag based, so do not loop it like the conditions*/
			if cyst_dx_dt=. | (Fst_Dt-cyst_dx_dt>(60)) then precyst=0; /*Within 60 days*/
			if proc_cd in('76857','76830') | 
			   proc1   in('76857','76830') | 
			   proc2   in('76857','76830') | 
			   proc3   in('76857','76830') then do;

			   precyst+1;
			   cyst_dx_dt=Fst_Dt;
			end;
		end;

	/*Upper Extremity Radiography*/
		if radiography_dt=. | (Fst_Dt - radiography_dt > (7)) then radiography = 0; /*If >7days since confirmed radiography claim, reset flag to 0*/

		if proc_cd in('25600', '25605', '25609', '25611', '73000', '73010', '73020', '73030', 
					  '73040', '73050','73090', '73092', '73100', '73110', '73115','73120', '73130', '73140','73200', 
					  '73201', '73202', '73206','73218', '73219', '73220', '73221','73222', '73223', '73225') |
		   			  '23600'<=:proc_cd<=:'23630' | '23665'<=:proc_cd<=:'23680' |
		   proc1 in('25600', '25605', '25609', '25611', '73000', '73010', '73020', '73030', 
					  '73040', '73050','73090', '73092', '73100', '73110', '73115','73120', '73130', '73140','73200', 
					  '73201', '73202', '73206','73218', '73219', '73220', '73221','73222', '73223', '73225') |
		   			  '23600'<=:proc1<=:'23630' | '23665'<=:proc1<=:'23680' |
		   proc2 in('25600', '25605', '25609', '25611', '73000', '73010', '73020', '73030', 
					  '73040', '73050','73090', '73092', '73100', '73110', '73115','73120', '73130', '73140','73200', 
					  '73201', '73202', '73206','73218', '73219', '73220', '73221','73222', '73223', '73225') |
		   			  '23600'<=:proc2<=:'23630' | '23665'<=:proc2<=:'23680' |
		   proc3 in('25600', '25605', '25609', '25611', '73000', '73010', '73020', '73030', 
					  '73040', '73050','73090', '73092', '73100', '73110', '73115','73120', '73130', '73140','73200', 
					  '73201', '73202', '73206','73218', '73219', '73220', '73221','73222', '73223', '73225') |
		   			  '23600'<=:proc3<=:'23630' | '23665'<=:proc3<=:'23680' then do;

			radiography = 1;
			radiography_dt = Fst_Dt;
		end;

	/*ED Visit Within 14 Days*/
		if ed14_dt=. | (Fst_Dt - ed14_dt > (14)) then ed14 = 0; /*If >14days since confirmed ED visit, reset flag to 0*/
		if pos in('23') then do;
			ed14=1;
			ed14_dt=Fst_Dt;
		end;

	/*Close the loop*/
	end;


	/*Create indicators for continuous enrollment in a given year*/
	%macro elig;
		%do i=2011 %to 2013;
			elig_&i.=0;
			%do j=1 %to &N.;
				if eligeff&j.<=mdy(1,1,&i.) & eligend&j.>=mdy(12,31,&i.) then elig_&i.=1;
			%end;
		%end;
	%mend;
	%elig;

	/*Calculate the look-back period on any given claim*/
	if year=2012 & elig_2011=1 then look_back=1;
	if year=2013 & elig_2012=1 then look_back=1;
	if year=2013 & elig_2011=1 & elig_2012=1 then look_back=2;

	/*Make a flag for emergency rooms visits*/
	ed=(pos="23");
run;

proc print data=med (obs=100);
	var patid fst_dt year elig_2011 elig_2012 elig_2013 look_back eligeff1 eligend1;
run;

/*Same as data step above, but had to re-sort by descending Fst_Dt since it checks if a procedure was
  done 30days BEFORE a surgery, as opposed to x-days after an event like above*/

proc sort data=med; by Patid descending Fst_Dt; run;

data out.low_value_build3;
	set med;
	by Patid;

	array proc [4] proc_cd proc1-proc3;
	array beto[4] betos betos1-betos3; 

	/*Non-Cardiothoracic Surgery, Surgery*/
	retain nc_surge nc_surge_dt
		   surge surge_dt
		   post_dialysis post_dial_dt
		   radiography radiography_dt;

	if first.Patid then do;
		nc_surge_dt = .;
		surge_dt = .;
		post_dial_dt = .;
		radiography_dt = .;

		nc_surge = 0; /*Indicates noncardiothoracic surgery coming up within 30days*/
		surge = 0;	  /*Indicates surgery coming up within 30days*/
		post_dialysis = 0; /*Indicates dialysis coming up within 30 days*/
		radiography = 0; /*Indicates upper body radiography coming up within 7 days*/
	end;
	
	do i=1 to dim(proc);
	/*Preoperative Testing Surgical Dates*/
		if proc[i] in('19120', '19125', '47562', '47563', '49560', '58558') |
		   beto[i] in ('P1x','P3D','P4A','P4B','P4C','P5C','P5D','P8A','P8G') |
		   substr(beto[i],1,2) in ('P1') then do; /*non-cardiothoracic surgery*/
			nc_surge_test=1;
			nc_surge=1;
			nc_surge_dt=Fst_Dt;
		end;
		if nc_surge_dt-Fst_Dt>30 | nc_surge_dt=. then nc_surge=0;

		if beto[i] in ('P1x','P2x','P3D','P4A','P4B','P4C','P5C','P5D','P8A','P8G') |
		   substr(beto[i],1,2) in ('P1','P2') then do;/*surgery*/
		    surge_test=1;
			surge=1;
			surge_dt=Fst_Dt;
		end;
		if surge_dt-Fst_Dt>30 | surge_dt=. then surge=0;
	end;

	/*Upcoming Dialysis Testing*/
		if betos in('P9A','P9B') | betos1 in('P9A','P9B') | betos2 in('P9A','P9B') | betos3 in('P9A','P9B') then do;
		    post_dialysis=1;
		    post_dial_dt=Fst_Dt;
		end;
		if post_dial_dt-Fst_Dt>30 | post_dial_dt=. then post_dialysis=0;

	/*Upper Extremity Radiography*/
		if proc_cd in('25600', '25605', '25609', '25611', '73000', '73010', '73020', '73030', 
					  '73040', '73050','73090', '73092', '73100', '73110', '73115','73120', '73130', '73140','73200', 
					  '73201', '73202', '73206','73218', '73219', '73220', '73221','73222', '73223', '73225') |
		   			  '23600'<=:proc_cd<=:'23630' | '23665'<=:proc_cd<=:'23680' |
		   proc1 in('25600', '25605', '25609', '25611', '73000', '73010', '73020', '73030', 
					  '73040', '73050','73090', '73092', '73100', '73110', '73115','73120', '73130', '73140','73200', 
					  '73201', '73202', '73206','73218', '73219', '73220', '73221','73222', '73223', '73225') |
		   			  '23600'<=:proc1<=:'23630' | '23665'<=:proc1<=:'23680' |
		   proc2 in('25600', '25605', '25609', '25611', '73000', '73010', '73020', '73030', 
					  '73040', '73050','73090', '73092', '73100', '73110', '73115','73120', '73130', '73140','73200', 
					  '73201', '73202', '73206','73218', '73219', '73220', '73221','73222', '73223', '73225') |
		   			  '23600'<=:proc2<=:'23630' | '23665'<=:proc2<=:'23680' |
		   proc3 in('25600', '25605', '25609', '25611', '73000', '73010', '73020', '73030', 
					  '73040', '73050','73090', '73092', '73100', '73110', '73115','73120', '73130', '73140','73200', 
					  '73201', '73202', '73206','73218', '73219', '73220', '73221','73222', '73223', '73225') |
		   			  '23600'<=:proc3<=:'23630' | '23665'<=:proc3<=:'23680' then do;

			radiography = 1;
			radiography_dt = Fst_Dt;
		end;
		if radiography_dt=. | (radiography_dt-Fst_dt > (7)) then radiography = 0; /*If >7days before confirmed radiography claim, reset flag to 0*/

run;

/*Make a flag for an inpatient confinement that includes an ED stay*/
proc sort data=out.low_value_build3; by conf_id descending ed; run;

data out.low_value_build3;
	set out.low_value_build3;
	retain ed_stay;
	by conf_id;
	if first.conf_id & conf_id~="" then ed_stay=ed; /*Flag all claims in a confinement that had at least 1 ED stay*/
run;

proc freq data=out.low_value_build3;
	tables 	
		CKD 
		prebone  
		dvt_pe 
		rec_dvt_pe  
		stroke_tia  
		ihd 
		dialysis  
		ost  
		b12_folate
		hyp_cal  
		sinusitis
		ami
		epilepsy
		arth  
		thyroid
		prepap  
		precyst
		nc_surge
		surge
		post_dialysis
		prov_cat / nocum nocol norow;
run;

/*Generate contents for the relevant Ingenix datasets*/
proc contents data=med out=med_cont (keep=NAME TYPE LENGTH VARNUM LABEL FORMAT); run;

/*********************
PRINT CHECK
*********************/
/*Output a sample of each of the datasets to an excel workbook*/
ods tagsets.excelxp file="&out./low_value2.xml" style=sansPrinter;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="Claims" frozen_headers='yes');
proc print data=out.low_value_build3 (obs=1000);
run;
ods tagsets.excelxp options(absolute_column_width='20' sheet_name="Med Contents" frozen_headers='yes');
proc print data=med_cont;
run;
ods tagsets.excelxp close;
/*********************
CHECK END
*********************/
