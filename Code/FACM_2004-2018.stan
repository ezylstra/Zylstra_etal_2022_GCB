data {

	// dimensions of data
	int<lower=1> n_counties;    // number of counties included in summer breeding region
	int<lower=1> n_years;       // number of years
	int<lower=1> n_cyw;         // n_counties * n_years * n_weeks
	int<lower=1> n_sites;       // number of unique summer survey locations
	int<lower=1> n_surveys;     // number of summer surveys
	int<lower=1> n_peak;        // number of county-year-week combinations during peak
	int<lower=1> n_cy;          // n_counties * n_years	

	// indices
	int<lower=1,upper=n_years>    year_id[n_cyw];            // year id (1:15)
	int<lower=1,upper=n_counties> county_id[n_cyw];          // county id (1:545)
	int<lower=1,upper=n_sites>    site_id[n_surveys];        // siteid (1:773)
	int<lower=1,upper=n_cyw>      cyw_id[n_surveys];         // id for colony-year-week combination
	int<lower=1>                  ind1[n_counties*n_years];  // used to calculate summer pop index
	int<lower=1>                  ind2[n_years];             // used to calculate summer pop index
	int<lower=1>                  start_peak;                // first row of X_county/week_st that has data for summer peak (wks 6-9)

	// number of regression coefficients
	int<lower=1> n_cov_alpha;   // number of fixed effects in county-level model (summer)
	int<lower=1> n_cov_beta;    // number of fixed effects in survey level model (summer)
	int<lower=1> n_cov_gamma;   // number of fixed effects in winter model
	
	// covariate data
	matrix[n_cyw,n_cov_alpha] X_county;    // matrix of covariates for summer county-level model (all standardized)
	vector[n_cyw] week_st;                 // week, in county-level model (standardized)
	matrix[n_surveys,n_cov_beta] X_survey; // matrix of covariates for summer survey-level model (all standardized)
	vector<lower=0>[n_surveys] effort;     // party hours spent on each survey (scaled or unscaled)
	matrix[n_years,n_cov_gamma] X_winter;  // matrix of covariates for winter model (all standardized)

	// response data
	int<lower=0> y_count[n_surveys];   // monarch count on each survey
	vector<lower=0>[n_years] area;     // area occupied by monarchs across all supercolonies (aggregated), each year
	
	// county weights (for calculating the summer index)
	vector<lower=0,upper=1>[n_counties] weights;  // based on non-forested area

}

parameters {

	// std normal variates (unscaled random intercepts)
	vector[n_counties]    countyRE_raw;
	vector[n_years]       weekRE_raw;
	vector[n_years]       week2RE_raw;
	vector[n_sites]       siteRE_raw;
	vector[n_years]       yearRE_raw;
	
	// regression coefficients
	vector[n_cov_alpha] alphaFE; // betas associated with fixed effects in county-level model
	real alphaRE_week;           // mean effect of week
	real alphaRE_week2;          // mean effect of week^2
	vector[n_cov_beta] betaFE;   // betas associated with fixed effects in survey-level model
	vector[n_cov_gamma] gammaFE; // beta associated with fixed effects in winter model (not including coef for summer index)
	real gamma_sum;              // effect of summer population size

	// intercepts
	real alpha0;                    // intercept in county-level model (mean expected count on NABA survey, on log scale)
	real gamma0;                    // intercept in winter, gamma model (mean area occupied when monarchs present, on log scale)

	// variance components (as std dev)
	real<lower=0> sd_county;     
  real<lower=0> sd_week; 
	real<lower=0> sd_week2;
	real<lower=0> sd_site;
	real<lower=0> sd_year;
	
	// gamma components for Gamma-Poisson mixture in summer model (= NB1 parameterization of Negative Binomial)
  vector<lower=0>[n_surveys] rho;  // gamma variates
	real<lower=0> r_count;           // shape/rate parameter (must be equal to ensure mean count = lambda)
	
	// shape parameter in Gamma distribution in winter model
	real<lower=0> shape;   	

}

transformed parameters {

	// expected count (on an average NABA survey with average effort) in each county, year, week
	vector<lower=0>[n_cyw] mu_county; 
	
	// expected count (on an average NABA survey with average effort) in each county, year, week ON LOG SCALE
	vector[n_cyw] mu_county_log; 

	// expected count on each survey (as a function of survey type, effort, local land use)
	vector<lower=0>[n_surveys] lambda;
	
	// parameter in Gamma-Poisson mixture (lambda * gamma)
	vector<lower=0>[n_surveys] lambda_star;	
	
	// mean area occupied in December
	vector<lower=0>[n_years] mu_win;
	
	// rate parameter for Gamma model (winter)
	vector<lower=0>[n_years] rate;
	
	// random effects
	vector[n_counties] randcounty;
	vector[n_years] randweek;
	vector[n_years] randweek2;
	vector[n_sites] randsite;
	vector[n_years] randyear;
	
	// objects associated with index of peak summer population size
	vector[n_peak] wk69;
	vector[n_counties*n_years] countyyr;
	vector[n_years] pred_orig_log;
	vector<lower=0>[n_years] pred_orig_exp;
	vector[n_years] pred_sum;
				
	randcounty = sd_county * countyRE_raw;
	randweek = sd_week * weekRE_raw;
	randweek2 = sd_week2 * week2RE_raw;
	randsite = sd_site * siteRE_raw;
	randyear = sd_year * yearRE_raw;

	// Summer: County-level model
	for(i in 1:n_cyw)
		mu_county_log[i] = alpha0 + (alphaRE_week + randweek[year_id[i]]) * week_st[i]
		                  + (alphaRE_week2 + randweek2[year_id[i]]) * week_st[i] * week_st[i]
		                  + X_county[i] * alphaFE + randcounty[county_id[i]];
	mu_county = exp(mu_county_log); 
									 
	// Getting index of "peak summer abundance" BEFORE EXPONENTIATING
	wk69 = segment(mu_county_log,start_peak,n_peak); // extracting weeks 6-9 (start_peak is first row with data from weeks 6-9)
	
	for(i in 1:n_cy)  // get means for each county-year combination BEFORE EXPONENTIATING
		countyyr[i] = mean(segment(wk69,ind1[i],4));

	for(i in 1:n_years)  // get weighted mean of counties in each year BEFORE EXPONENTIATING
		pred_orig_log[i] = sum(weights .* segment(countyyr,ind2[i],n_counties));
	
	pred_orig_exp = exp(pred_orig_log); // get weighted mean of counties in each year

	pred_sum = (pred_orig_log - 1.12) ./ 0.59;

	// Summer: Survey-level model
	for(i in 1:n_surveys)
		lambda[i] = exp(mu_county_log[cyw_id[i]] + log(effort[i]) 
		            + X_survey[i] * betaFE + randsite[site_id[i]]);
	
	lambda_star = lambda .* rho;

	// Winter: Gamma model
	for(i in 1:n_years)
		mu_win[i] = exp(gamma0 + gamma_sum * pred_sum[i] + X_winter[i] * gammaFE + randyear[i]); 

	rate = shape ./ mu_win;
}

model {

	// priors on variance components
	target += cauchy_lpdf(sd_county   | 0, 1);
	target += cauchy_lpdf(sd_week     | 0, 1);
	target += cauchy_lpdf(sd_week2    | 0, 1);
	target += cauchy_lpdf(sd_site     | 0, 1);
	target += cauchy_lpdf(sd_year     | 0, 1);
	
	// priors on intercepts and regression coefficients (implicit U(0,1) prior on pocc_mn) 
	target += normal_lpdf(alphaFE       | 0, sqrt(1000));
	target += normal_lpdf(betaFE        | 0, sqrt(1000));
	target += normal_lpdf(gammaFE       | 0, sqrt(1000));
	target += normal_lpdf(alpha0        | 0, sqrt(1000));	
	target += normal_lpdf(alphaRE_week  | 0, sqrt(1000));
	target += normal_lpdf(alphaRE_week2 | 0, sqrt(1000)); 
	target += normal_lpdf(gamma0        | 0, sqrt(1000));
	target += normal_lpdf(gamma_sum     | 0, sqrt(1000));
	
	// prior for shape/rate in Gamma-Poisson mixture (summer model)
	target += uniform_lpdf(r_count | 0, 20);
	
	// prior for shape parameter in Gamma model (winter)
	target += gamma_lpdf(shape | 2, 2);
	
	// unscaled random intercepts/slopes
	target += std_normal_lpdf(countyRE_raw);
	target += std_normal_lpdf(weekRE_raw);
	target += std_normal_lpdf(week2RE_raw);
	target += std_normal_lpdf(siteRE_raw);
	target += std_normal_lpdf(yearRE_raw);
	
	// gamma variates for Gamma-Poisson mixture
	target += gamma_lpdf(rho | r_count, r_count);
	
	// Modeling counts in summer (Gamma-Poisson mixture)
	target += poisson_lpmf(y_count | lambda_star);	
	
	// Modeling area occupied in winter (Gamma hurdle model)
	for(i in 1:n_years)
	target += gamma_lpdf(area[i] | shape, rate[i]);

}

