version 17.0
clear all
do "D:/ANU/s4/8100/ass/SY/code/00_config.do"
capture log close _all
log using "$logs/verification.log", text replace

capture confirm file "$clean/daily_panel.dta"
if !_rc {
    use "$clean/daily_panel.dta", clear
    isid firm_id date
    assert ret>-1 if !missing(ret)
    assert inrange(retail_share,0,1) if !missing(retail_share)
    assert abs(retail_share-(retail_buy+retail_sell)/(2*total_value))<1e-10 if retail_valid
    count
    display "DAILY_PANEL_ROWS=" r(N)
    gen int calendar_year=year(date)
    preserve
        collapse (count) firm_days=firm_id valid_returns=ret matched_retail=retail_share, by(calendar_year)
        write_csv using "$audit/verified_daily_coverage.csv", replace
    restore
}
else display "daily_panel.dta not in SY/data/clean (00_clean.do not run here): daily checks skipped."

use "$clean/regression_panel_with_samples.dta", clear
isid firm_id event_id
assert _N==128*16
assert sample_rep5583==1
preserve
    import delimited using "$sample_drop", encoding("utf-8") stringcols(_all) clear
    unab allv : _all
    local first : word 1 of `allv'
    if "`first'"!="repetition" rename `first' repetition
    keep stock_code
    tempfile dl
    save `dl'
restore
merge m:1 stock_code using `dl', keep(master match)
assert _merge==1
drop _merge
assert inlist(d,0,1) if linked
assert missing(d) if !linked
assert d==(link_s & link_h) if linked
assert abs(r-(retail_pre-.50)/.10)<1e-10 if !missing(r)
assert abs(dz-d*z)<1e-10 if !missing(dz)
assert abs(drz-d*r*z)<1e-10 if !missing(drz)
assert retail_ok<=base_ok & eps_ok<=base_ok
assert triple_ok==(retail_ok & eps_ok)
assert sample_m1==base_ok
assert sample_m5==eps_ok
assert n_est>=120 if base_ok
assert !missing(car02,size,prior,risk,turn) if base_ok
foreach sample in base_ok retail_ok eps_ok triple_ok {
    quietly count if `sample'
    local observations=r(N)
    quietly levelsof firm_id if `sample', local(companies)
    local firms : word count `companies'
    quietly levelsof event_id if `sample', local(events)
    local nevents : word count `events'
    display "`sample': observations=`observations'; firms=`firms'; events=`nevents'"
}
preserve
    keep if base_ok
    contract stock_code company_name customer_group
    rename _freq firm_events
    write_csv using "$audit/verified_sample_companies.csv", replace
restore

use "$tables/main_coefficients.dta", clear
isid model term
assert se>0 & !missing(coefficient,se,p,ci_low,ci_high)
assert inrange(p,0,1)
assert ci_low<=coefficient & ci_high>=coefficient
assert firms>=2 & events>=2
list model term coefficient se p n if inlist(term,"d","dz","drz"), noobs
display "VERIFICATION PASSED: data keys, formulas and sample flags agree."
log close
