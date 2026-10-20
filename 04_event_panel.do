tempfile events eventindex grid coefficients outcomes rels linkflags weights

use "$clean/eps_event_signal.dta", clear
local expected_events=_N
cross using "$clean/kr_calendar.dta"
keep if (missing(kr_override) & date>us_date) | (!missing(kr_override) & date==kr_override)
bysort event_id (date): keep if _n==1
assert _N==`expected_events'
rename (date t) (event_date t0)
drop year
preserve
    keep event_id t0
    gen int t=t0-6
    merge m:1 t using "$clean/kr_calendar.dta", keepusing(date) keep(master match) nogen
    rename date ref_date
    keep event_id ref_date
    save `events'
restore
merge 1:1 event_id using `events', nogen
assert !missing(event_date,ref_date)
isid event_id
save "$clean/event_calendar.dta", replace
save `events', replace
preserve
    keep event_id t0
    save `eventindex'
restore
use "$clean/company_master.dta", clear
cross using `events'
isid firm_id event_id
save `grid'

use "$clean/daily_panel.dta", clear
cross using `eventindex'
gen int k=t-t0
keep if inrange(k,-250,20)
isid firm_id event_id k
save "$tmp/firm_event_daily.dta", replace

preserve
    keep if inrange(k,-250,-31) & !missing(ret,sox_ret)
    bysort firm_id event_id: gen int paired_days=_N
    bysort firm_id event_id: egen double sd_sox=sd(sox_ret)
    keep if paired_days>=$min_est & sd_sox>0 & !missing(sd_sox)
    count
    if r(N)==0 {
        display as error "No firm-event has enough estimation days. Check daily data."
        exit 2000
    }
    statsby alpha=_b[_cons] beta=_b[sox_ret] n_est=e(N), by(firm_id event_id) clear: regress ret sox_ret
    isid firm_id event_id
    save `coefficients'
restore
merge m:1 firm_id event_id using `coefficients', keep(master match) nogen
gen double ar=ret-alpha-beta*sox_ret if n_est>=$min_est & !missing(n_est,ret,sox_ret)
gen double abs_ar=abs(ar)

foreach w in 01 02 03 320 {
    local a=0
    local b=real("`w'")
    if "`w'"=="320" {
        local a=3
        local b=20
    }
    bysort firm_id event_id: egen int n_car`w'=total(inrange(k,`a',`b') & !missing(ar))
    bysort firm_id event_id: egen double car`w'=total(cond(inrange(k,`a',`b'),100*ar,.))
    replace car`w'=. if n_car`w'!=`b'-`a'+1
}
bysort firm_id event_id: egen int n_prior=total(inrange(k,-60,-6) & !missing(ret))
bysort firm_id event_id: egen double prior_log=total(cond(inrange(k,-60,-6),ln(1+ret),.))
gen double prior=exp(prior_log)-1 if n_prior==55
bysort firm_id event_id: egen double risk=sd(cond(inrange(k,-60,-6),ret,.))
replace risk=. if n_prior<$min_pre
bysort firm_id event_id: egen double size=max(cond(k==-6,ln(market_cap),.))
bysort firm_id event_id: egen byte market_pre=max(cond(k==-6,market_ok,.))
bysort firm_id event_id: egen int n_turn=total(inrange(k,-20,-6) & !missing(turnover))
bysort firm_id event_id: egen double turn=mean(cond(inrange(k,-20,-6),turnover,.))
replace turn=. if n_turn<$min_base

foreach w in pre base post {
    if "`w'"=="pre"  local a=-60
    if "`w'"=="base" local a=-20
    if "`w'"=="post" local a=0
    local b=-6
    if "`w'"=="post" local b=2
    gen byte use_`w'=inrange(k,`a',`b') & retail_valid==1
    bysort firm_id event_id: egen int n_ret_`w'=total(use_`w')
    bysort firm_id event_id: egen double numer_`w'=total(cond(use_`w',retail_buy+retail_sell,.))
    bysort firm_id event_id: egen double denom_`w'=total(cond(use_`w',2*total_value,.))
    gen double retail_`w'=numer_`w'/denom_`w' if denom_`w'>0
}
replace retail_pre=. if n_ret_pre<$min_pre
replace retail_base=. if n_ret_base<$min_base
replace retail_post=. if n_ret_post!=3
gen double r=(retail_pre-0.50)/0.10
gen double delta_retail=100*(retail_post-retail_base)
bysort firm_id event_id: egen int n_abs_base=total(inrange(k,-20,-6) & !missing(abs_ar))
bysort firm_id event_id: egen double abs_base=mean(cond(inrange(k,-20,-6),abs_ar,.))
bysort firm_id event_id: egen double abs_post=mean(cond(inrange(k,0,2),abs_ar,.))
gen double delta_abs=100*(abs_post-abs_base) if n_abs_base>=$min_base & n_car02==3
keep firm_id event_id alpha beta n_est car* n_car* prior risk size turn market_pre n_prior n_turn retail_pre r n_ret_pre delta_retail delta_abs
bysort firm_id event_id: keep if _n==1
isid firm_id event_id
save `outcomes'

import delimited "$links", clear varnames(1) stringcols(_all) encoding("utf-8")
keep if rel_type=="CUSTOMER" & inlist(target_company_id,"1835724","1401901")
rename source_company_id company_id
gen double rel_start=daily(start_,"YMD")
gen double rel_end=daily(end_,"YMD")
gen byte interval_ok=!missing(rel_start,rel_end) & rel_start<rel_end
preserve
    keep if !interval_ok
    write_csv using "$audit/relationship_bad_intervals.csv", replace
restore
keep if interval_ok
keep company_id target_company_id rel_start rel_end id revenue_percent percent_estimated
duplicates drop
save `rels'
use `grid', clear
keep firm_id event_id company_id ref_date
joinby company_id using `rels', unmatched(master)
gen byte active=rel_start<=ref_date & ref_date<rel_end & !missing(rel_start,rel_end,ref_date)
gen byte link_s=active & target_company_id=="1835724"
gen byte link_h=active & target_company_id=="1401901"
preserve
    keep if active
    write_csv using "$audit/active_relationship_evidence.csv", replace
restore
collapse (max) link_s link_h, by(firm_id event_id)
gen byte linked=link_s | link_h
gen byte d=link_s & link_h if linked
gen byte customer_group=1 if link_s & !link_h
replace customer_group=2 if link_h & !link_s
replace customer_group=3 if link_s & link_h
label define groups 1 "Samsung only" 2 "SK hynix only" 3 "Both"
label values customer_group groups
save `linkflags'

use `grid', clear
merge 1:1 firm_id event_id using `outcomes', keep(master match) nogen
merge 1:1 firm_id event_id using `linkflags', assert(match) nogen
gen byte base_ok=role=="SUPPLIER_CANDIDATE" & include_candidate==1 & market_pre==1 & linked==1 & !missing(car02,size,prior,risk,turn)
gen byte review_ok=identity_verified==1 & timing_verified==1
if $strict_review==1 replace base_ok=0 if !review_ok
gen byte retail_ok=base_ok & !missing(r)
gen byte eps_ok=base_ok & signal_candidate_ok==1 & !missing(z)
if $strict_review==1 replace eps_ok=0 if signal_reviewed!=1
gen byte triple_ok=eps_ok & retail_ok
gen byte provisional=1
replace provisional=0 if review_ok & signal_reviewed
gen byte review_mode=$strict_review
label variable review_mode "Build mode: 0=provisional; 1=manually reviewed restrictions"

foreach x in size prior risk turn {
    gen double `x'_w=`x'
    quietly count if base_ok & !missing(`x')
    if r(N)>0 {
        quietly _pctile `x' if base_ok, p(1 99)
        local lo=r(r1)
        local hi=r(r2)
        replace `x'_w=max(`lo',min(`hi',`x')) if !missing(`x')
        display "Winsor `x': `lo' to `hi'"
    }
}
gen double dr=d*r
gen double dz=d*z
gen double rz=r*z
gen double drz=d*r*z
label variable d "1=both core customer links; 0=one link; missing=no link"
label variable r "Pre-event retail share centered at .50 and scaled by .10"
label variable car02 "CAR[0,2], SOX benchmark, percentage points"
label variable delta_abs "Change in mean absolute abnormal return; percentage points"
isid firm_id event_id
save "$clean/regression_panel.dta", replace

gen str50 exclusion="eligible baseline"
replace exclusion="core / manually excluded candidate" if role!="SUPPLIER_CANDIDATE" | include_candidate!=1
replace exclusion="market or day -6 price unavailable" if exclusion=="eligible baseline" & market_pre!=1
replace exclusion="incomplete SOX model or CAR" if exclusion=="eligible baseline" & missing(car02)
replace exclusion="no active historical customer record" if exclusion=="eligible baseline" & linked!=1
replace exclusion="incomplete pre-event controls" if exclusion=="eligible baseline" & missing(size,prior,risk,turn)
if $strict_review==1 replace exclusion="manual review incomplete" if exclusion=="eligible baseline" & !review_ok
write_csv using "$audit/firm_event_screens.csv", replace
preserve
    contract exclusion
    write_csv using "$audit/sample_flow.csv", replace
restore
preserve
    collapse (sum) baseline=base_ok retail=retail_ok eps=eps_ok triple=triple_ok, by(event_id event_key us_date event_date)
    write_csv using "$audit/event_sample_counts.csv", replace
restore

use "$clean/regression_panel.dta", clear
keep if 0
foreach v in w_h w_s eh es_customer ehz esz d_rev omega_h {
    gen double `v'=.
}
save "$clean/weighted_panel.dta", replace
import delimited "$code/inputs/customer_weights_review.csv", clear varnames(1) stringcols(_all) encoding("utf-8")
count
if r(N)>0 {
    destring w_h w_s approved, replace
    keep if approved==1
    count
    if r(N)>0 {
        gen double publication_date=daily(publication_date_text,"YMD")
        gen double fiscal_end=daily(fiscal_end_text,"YMD")
        assert !missing(publication_date,fiscal_end,w_h,w_s)
        assert weight_source_url!="" & weight_note!=""
        assert inrange(w_h,0,1) & inrange(w_s,0,1) & w_h+w_s<=1.000001
        assert publication_date>fiscal_end
        isid stock_code fiscal_end publication_date
        save `weights'
        use "$clean/regression_panel.dta", clear
        joinby stock_code using `weights', unmatched(none)
        keep if publication_date<ref_date & fiscal_end<ref_date
        bysort firm_id event_id (fiscal_end publication_date): keep if _n==_N
        gen double eh=w_h/0.10
        gen double es_customer=w_s/0.10
        gen double ehz=eh*z
        gen double esz=es_customer*z
        gen double d_rev=w_h+w_s
        gen double omega_h=w_h/(w_h+w_s) if w_h+w_s>0
        isid firm_id event_id
        save "$clean/weighted_panel.dta", replace
    }
}
