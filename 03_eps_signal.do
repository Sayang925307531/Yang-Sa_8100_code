tempfile events actuals stopped forecasts consensus priceevent

import delimited "$code/inputs/event_review.csv", clear varnames(1) stringcols(_all) encoding("utf-8")
destring event_id official_eps_adj timing_verified eps_basis_verified actual_vintage_verified prior_prelim, replace
gen double us_date=daily(us_date_text,"YMD")
gen double fpedate=daily(ibes_period_end,"YMD")
gen double kr_override=daily(kr_event_date_verified,"YMD")
gen double price_date_override=daily(nvda_price_date_verified,"YMD")
isid event_id
isid us_date
assert !missing(us_date,fpedate)
assert inlist(timing_verified,0,1) & inlist(eps_basis_verified,0,1)
assert inlist(actual_vintage_verified,0,1)
assert !missing(kr_override,price_date_override) if timing_verified==1
assert price_date_override<=us_date if !missing(price_date_override)
assert kr_override>=us_date if !missing(kr_override)
assert event_note!="" if timing_verified | eps_basis_verified | actual_vintage_verified
save `events'

import delimited "$ibes/wrds_ibes_nvda_actuals_EPS_GPS_SAL_2021-2025_raw_20261010.csv", clear varnames(1) case(lower) stringcols(_all)
keep if ticker=="NVDA" & measure=="EPS" & pdicity=="QTR"
gen double us_date=daily(anndats,"YMD")
gen double fpedate=daily(pends,"YMD")
gen double eps_actual=real(value)
gen double actual_activation=daily(actdats,"YMD")
assert curr_act=="USD" & usfirm=="1"
keep us_date fpedate eps_actual actual_activation anntims
isid us_date fpedate
save `actuals'
use `events', clear
merge 1:1 us_date fpedate using `actuals', generate(actual_merge)
drop if actual_merge==2
gen byte actual_matches_release=abs(eps_actual-official_eps_adj)<=0.001 & !missing(eps_actual,official_eps_adj)
save `events', replace

import delimited "$ibes/wrds_ibes_nvda_stopped_EPS_GPS_fperiod_2021-2026Q1_raw_20261010.csv", clear varnames(1) case(lower) stringcols(_all)
keep if ticker=="NVDA" & measure=="EPS" & pdicity=="Q"
gen double fpedate=daily(fpedats,"YMD")
gen double stop_date=daily(astpdats,"YMD")
keep estimator fpedate stop_date
duplicates drop
save `stopped'

import delimited "$ibes/wrds_ibes_nvda_detail_EPS_GPS_SAL_2021-2025_raw_20261010.csv", clear varnames(1) case(lower) stringcols(_all)
keep if ticker=="NVDA" & measure=="EPS" & inlist(fpi,"6","7","8","9")
keep if pdf=="D" & usfirm=="1" & report_curr=="USD" & inlist(curr,"","USD")
gen double fpedate=daily(fpedats,"YMD")
gen double forecast_date=daily(anndats,"YMD")
gen double activation_date=daily(actdats,"YMD")
gen double forecast_clock=clock(anndats+" "+anntims,"YMDhms")
gen double activation_clock=clock(actdats+" "+acttims,"YMDhms")
gen double eps_forecast=real(value)
keep estimator analys fpedate forecast_date activation_date forecast_clock activation_clock eps_forecast
gen long forecast_row=_n
joinby fpedate using `events', unmatched(none)
gen int forecast_age=us_date-forecast_date
keep if forecast_date<us_date & activation_date<us_date & inrange(forecast_age,1,$forecast_age)
keep if !missing(eps_forecast,forecast_clock,activation_clock) & estimator!=""
joinby estimator fpedate using `stopped', unmatched(master)
gen byte stopped_before_event=stop_date<us_date & stop_date>=forecast_date & !missing(stop_date)
bysort event_id forecast_row: egen byte any_stop=max(stopped_before_event)
by event_id forecast_row: keep if _n==1
drop if any_stop
drop _merge stop_date stopped_before_event any_stop
save `forecasts'

forvalues agepass=1/2 {
    use `forecasts', clear
    if `agepass'==2 keep if forecast_age<=90
    bysort event_id estimator (forecast_clock activation_clock): keep if forecast_clock==forecast_clock[_N] & activation_clock==activation_clock[_N]
    bysort event_id estimator: egen double min_f=min(eps_forecast)
    bysort event_id estimator: egen double max_f=max(eps_forecast)
    preserve
        keep if min_f!=max_f
        write_csv using "$audit/ibes_tied_conflicts_`agepass'.csv", replace
    restore
    drop if min_f!=max_f
    count
    if r(N)==0 {
        display as error "No usable broker forecasts for age pass `agepass'. Inspect IBES filters."
        exit 2000
    }
    bysort event_id estimator (analys): keep if _n==1
    isid event_id estimator
    if `agepass'==1 save "$clean/ibes_broker_event.dta", replace
    collapse (mean) consensus=eps_forecast (median) consensus_median=eps_forecast (count) n_brokers=eps_forecast, by(event_id)
    if `agepass'==1 save `consensus'
    if `agepass'==2 {
        rename (consensus consensus_median n_brokers) (consensus90 median90 n_brokers90)
        merge 1:1 event_id using `consensus', nogen
        save `consensus', replace
    }
}

use `events', clear
gen double price_cutoff=us_date
replace price_cutoff=price_date_override if !missing(price_date_override)
rename us_date release_date
cross using "$clean/us_daily.dta"
keep if us_date<=price_cutoff
bysort event_id (us_date): keep if _n==_N
rename us_date nvda_price_date
rename release_date us_date
keep event_id nvda_price_date nvda_price_adj
isid event_id
save `priceevent'

use `events', clear
merge 1:1 event_id using `consensus', nogen
merge 1:1 event_id using `priceevent', nogen
assert nvda_price_date==price_date_override if !missing(price_date_override)
gen byte signal_candidate_ok=n_brokers>=$min_brokers & !missing(n_brokers,eps_actual,consensus,nvda_price_adj) & nvda_price_adj>0 & actual_matches_release
gen double ue=eps_actual-consensus if signal_candidate_ok
gen double es=ue/nvda_price_adj if signal_candidate_ok
gen double z=es/0.001
gen double z_median=(eps_actual-consensus_median)/nvda_price_adj/0.001 if signal_candidate_ok
gen double z90=(eps_actual-consensus90)/nvda_price_adj/0.001 if signal_candidate_ok & n_brokers90>=$min_brokers & !missing(n_brokers90)
gen byte signal_reviewed=signal_candidate_ok & eps_basis_verified==1 & timing_verified==1 & actual_vintage_verified==1
label variable z "EPS surprise / split-consistent price / 0.001"
label variable ue "Unexpected EPS; USD/share on post-2024 split basis"
label variable actual_matches_release "Numeric EPS cross-check only; not first-vintage validation"
format us_date fpedate nvda_price_date kr_override %tdCCYY-NN-DD
isid event_id
save "$clean/eps_event_signal.dta", replace
write_csv using "$audit/eps_event_signal_review.csv", replace
