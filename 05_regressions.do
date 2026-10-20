use "$clean/regression_panel.dta", clear
isid firm_id event_id
assert review_mode==$strict_review
global controls "size_w prior_w risk_w turn_w"
display "strict_review=$strict_review (0 means provisional research sample)"

count if base_ok
if r(N)==0 {
    display as error "No baseline sample. Inspect firm_event_screens.csv and review mode."
    exit 2000
}
quietly summarize d if base_ok
assert r(min)<r(max)
levelsof event_id if base_ok, local(evlist)
local ge : word count `evlist'
assert `ge'>=2
levelsof firm_id if base_ok, local(firmlist)
local gf : word count `firmlist'
assert `gf'>=2

estpost summarize car02 d retail_pre r z size prior risk turn if base_ok, detail
esttab using "$tables/descriptive_statistics.csv", replace cells("count mean sd p25 p50 p75 min max") nonumber nomtitle
preserve
    keep if base_ok
    contract event_id customer_group
    write_csv using "$audit/customer_group_support.csv", replace
restore

eststo clear
reghdfe car02 d $controls if base_ok, absorb(event_id) vce(cluster firm_id event_id)
assert _se[d]>0 & !missing(_se[d])
eststo M1
gen byte sample_m1=e(sample)
test d
scalar p_h1=r(p)
scalar p_h2=.
scalar p_wild_h1=.
scalar p_wild_h2=.
local models M1
boottest d, cluster(firm_id event_id) bootcluster(event_id) weight(webb) reps($bootstrap_reps) seed(810017) nograph
scalar p_wild_h1=r(p)

count if retail_ok
if r(N)>0 {
    reghdfe car02 d $controls if retail_ok, absorb(event_id) vce(cluster firm_id event_id)
    eststo M2
    reghdfe car02 d r dr $controls if retail_ok, absorb(event_id) vce(cluster firm_id event_id)
    eststo M3
    local models `models' M2 M3
}

count if eps_ok
if r(N)>0 {
    reghdfe car02 d $controls if eps_ok, absorb(event_id) vce(cluster firm_id event_id)
    eststo M4
    reghdfe car02 d dz $controls if eps_ok, absorb(event_id) vce(cluster firm_id event_id)
    assert _se[dz]>0 & !missing(_se[dz])
    eststo M5
    gen byte sample_m5=e(sample)
    test dz
    scalar p_h2=r(p)
    boottest dz, cluster(firm_id event_id) bootcluster(event_id) weight(webb) reps($bootstrap_reps) seed(810017) nograph
    scalar p_wild_h2=r(p)
    local models `models' M4 M5
}

count if triple_ok
if r(N)>0 {
    reghdfe car02 d r dr dz rz drz $controls if triple_ok, absorb(event_id) vce(cluster firm_id event_id)
    eststo M6
    local models `models' M6
    if _se[drz]>0 & !missing(_se[drz]) {
        boottest drz, cluster(firm_id event_id) bootcluster(event_id) weight(webb) reps($bootstrap_reps) seed(810017) nograph
        quietly summarize r if e(sample) & d==0, detail
        local low0=r(p25)
        local high0=r(p75)
        quietly summarize r if e(sample) & d==1, detail
        local low=max(`low0',r(p25))
        local high=min(`high0',r(p75))
        if `low'<=`high' {
            local mid=(`low'+`high')/2
            lincom dz+`low'*drz
            lincom dz+`mid'*drz
            lincom dz+`high'*drz
        }
    }
}
esttab `models' using "$tables/main_models.csv", replace b(4) se(4) stats(N N_clust1 N_clust2 r2, labels("Observations" "Firm clusters" "Event clusters" "R-squared")) nostar
esttab `models' using "$tables/main_models.rtf", replace b(4) se(4) stats(N N_clust1 N_clust2 r2) nostar
esttab `models' using "$tables/main_models_ci.csv", replace b(4) ci(4) stats(N N_clust1 N_clust2 r2) nostar
capture mkdir "$results/estimates"
tempname coefficients
postfile `coefficients' str4 model str32 term double coefficient se p ci_low ci_high n firms events df_r f_stat using "$tables/main_coefficients.dta", replace
foreach model of local models {
    estimates restore `model'
    estimates save "$results/estimates/`model'.ster", replace
    local terms : colnames e(b)
    foreach term of local terms {
        local p=cond(_se[`term']>0,2*ttail(e(df_r),abs(_b[`term']/_se[`term'])),.)
        local margin=invttail(e(df_r),.025)*_se[`term']
        post `coefficients' ("`model'") ("`term'") (_b[`term']) (_se[`term']) (`p') (_b[`term']-`margin') (_b[`term']+`margin') (e(N)) (e(N_clust1)) (e(N_clust2)) (e(df_r)) (e(F))
    }
}
postclose `coefficients'
preserve
    use "$tables/main_coefficients.dta", clear
    write_csv using "$tables/main_coefficients.csv", replace
restore
save "$clean/regression_panel_with_samples.dta", replace

preserve
    clear
    set obs 2
    gen str8 hypothesis=cond(_n==1,"H1","H2")
    gen double p_raw=cond(_n==1,scalar(p_h1),scalar(p_h2))
    gen double p_wild=cond(_n==1,scalar(p_wild_h1),scalar(p_wild_h2))
    foreach method in raw wild {
        gen double holm_`method'=.
        count if missing(p_`method')
        if r(N)==0 {
            sort p_`method'
            replace holm_`method'=min(1,2*p_`method') in 1
            replace holm_`method'=max(holm_`method'[1],p_`method') in 2
        }
    }
    sort hypothesis
    gen byte review_mode=$strict_review
    write_csv using "$tables/primary_tests_holm.csv", replace
restore

preserve
    keep if sample_m1
    contract event_id
    write_csv using "$tables/baseline_observations_by_event.csv", replace
restore
