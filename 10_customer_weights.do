version 17.0
local wdir "$out/customer_weights/final"

capture program drop _fix_first
program define _fix_first
    unab allv : _all
    local first : word 1 of `allv'
    if "`first'"!="stock_code" rename `first' stock_code
end

tempfile cal wts
import delimited using "`wdir'/annual_report_calendar_SY118.csv", encoding("utf-8") varnames(1) stringcols(1) clear
_fix_first
keep stock_code fiscal_year public_by_date
gen double pub=daily(public_by_date,"YMD")
format pub %td
assert !missing(pub)
assert regexm(stock_code,"^[0-9][0-9][0-9][0-9][0-9][0-9]$")
isid stock_code fiscal_year
drop public_by_date
save `cal'

import delimited using "`wdir'/customer_weights_firm_year_FINAL.csv", encoding("utf-8") varnames(1) stringcols(1) clear
_fix_first
keep stock_code fiscal_year w_h w_s w_h_alt w_s_alt both_known flags
foreach v in w_h w_s w_h_alt w_s_alt {
    capture confirm string variable `v'
    if !_rc destring `v', replace force
}
isid stock_code fiscal_year
assert inrange(w_h,0,1) | missing(w_h)
assert inrange(w_s,0,1) | missing(w_s)
assert w_h+w_s<=1.000001 if !missing(w_h,w_s)
save `wts'

use "$clean/regression_panel.dta", clear
assert sample_rep5583==1
keep if base_ok==1
keep stock_code company_name firm_id event_id ref_date base_ok retail_ok eps_ok car02 d z r size_w prior_w risk_w turn_w
joinby stock_code using `cal'
keep if pub<ref_date
bysort firm_id event_id (fiscal_year): keep if _n==_N
merge m:1 stock_code fiscal_year using `wts', keep(master match) nogen
gen long report_age_days=ref_date-pub
gen double eh=w_h/0.10
gen double es_customer=w_s/0.10
gen double ehz=eh*z
gen double esz=es_customer*z
gen byte w_both=!missing(w_h,w_s)
gen byte w_h_known=!missing(w_h)
gen byte w_s_known=!missing(w_s)
gen byte parent_overlap=strpos(flags,"parent_overlap")>0
label variable w_h "Sales to SK hynix / consolidated revenue, latest annual report before ref_date"
label variable w_s "Sales to Samsung Electronics / consolidated revenue, latest annual report before ref_date"
label variable eh "w_h/0.10 (per 10 pp)"
label variable es_customer "w_s/0.10 (per 10 pp)"
isid firm_id event_id
save "$clean/customer_weight_event_panel.dta", replace
preserve
    keep if w_h_known | w_s_known
    write_csv using "$audit/customer_weight_event_matches.csv", replace
restore

tempname cov
postfile `cov' str6 family str8 sample long obs firms events dual single using "$tables/customer_weight_coverage.dta", replace
foreach fam in both h s {
    local cond "w_both"
    if "`fam'"=="h" local cond "w_h_known"
    if "`fam'"=="s" local cond "w_s_known"
    foreach smp in base_ok eps_ok {
        quietly count if `cond' & `smp'
        local n=r(N)
        local fl ""
        local el ""
        capture levelsof firm_id if `cond' & `smp', local(fl)
        capture levelsof event_id if `cond' & `smp', local(el)
        local nf : word count `fl'
        local ne : word count `el'
        quietly count if `cond' & `smp' & d==1
        local nd=r(N)
        post `cov' ("`fam'") ("`smp'") (`n') (`nf') (`ne') (`nd') (`n'-`nd')
        local nf_`fam'_`smp'=`nf'
        local ne_`fam'_`smp'=`ne'
    }
}
postclose `cov'
preserve
    use "$tables/customer_weight_coverage.dta", clear
    write_csv using "$tables/customer_weight_coverage.csv", replace
    list, noobs
restore

preserve
    keep if w_h_known | w_s_known
    collapse (count) firm_events=event_id (mean) w_h_mean=w_h w_s_mean=w_s d_share=d ///
        (min) w_h_min=w_h w_s_min=w_s first_fy=fiscal_year (max) w_h_max=w_h w_s_max=w_s last_fy=fiscal_year parent_overlap, ///
        by(stock_code company_name)
    write_csv using "$tables/customer_weight_descriptives.csv", replace
    list stock_code company_name firm_events w_h_mean w_s_mean d_share, noobs
restore

global controls "size_w prior_w risk_w turn_w"
tempname status
file open `status' using "$results/CUSTOMER_WEIGHT_STATUS.txt", write replace text
file write `status' "SY customer sales weights (Samsung Electronics / SK hynix); run date: `c(current_date)'" _n
file write `status' "Rule: latest annual report filed before ref_date; missing disclosure stays missing; estimate only if >=10 firms and >=5 events in EPS sample." _n
foreach fam in both h s {
    local cond "w_both"
    local rhs "eh es_customer ehz esz"
    if "`fam'"=="h" {
        local cond "w_h_known"
        local rhs "eh ehz"
    }
    if "`fam'"=="s" {
        local cond "w_s_known"
        local rhs "es_customer esz"
    }
    local nf=`nf_`fam'_eps_ok'
    local ne=`ne_`fam'_eps_ok'
    if `nf'>=10 & `ne'>=5 {
        reghdfe car02 d $controls if eps_ok & `cond', absorb(event_id) vce(cluster firm_id event_id)
        estimates store W_`fam'_D
        reghdfe car02 `rhs' $controls if eps_ok & `cond', absorb(event_id) vce(cluster firm_id event_id)
        estimates store W_`fam'
        esttab W_`fam'_D W_`fam' using "$tables/customer_weights_`fam'.csv", replace b(4) se(4) stats(N N_clust1 N_clust2) nostar
        esttab W_`fam'_D W_`fam' using "$tables/customer_weights_`fam'.rtf", replace b(4) se(4) stats(N N_clust1 N_clust2) nostar
        file write `status' "ESTIMATED family=`fam': firms=`nf' events=`ne'" _n
    }
    else {
        file write `status' "NOT ESTIMATED family=`fam': EPS-sample firms=`nf' events=`ne' (prespecified minimum 10 firms / 5 events)." _n
        display "NOT ESTIMATED family=`fam': firms=`nf' events=`ne'"
    }
}
file close `status'
display "CUSTOMER WEIGHTS STEP FINISHED"
