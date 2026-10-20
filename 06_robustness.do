use "$clean/regression_panel.dta", clear
global controls "size_w prior_w risk_w turn_w"
eststo clear
local models ""

foreach y in car01 car03 car320 delta_abs delta_retail {
    count if base_ok & !missing(`y')
    if r(N)>0 {
        reghdfe `y' d $controls if base_ok, absorb(event_id) vce(cluster firm_id event_id)
        eststo B_`y'
        local models `models' B_`y'
    }
}
count if base_ok & n_est>=160 & !missing(n_est)
if r(N)>0 {
    reghdfe car02 d $controls if base_ok & n_est>=160, absorb(event_id) vce(cluster firm_id event_id)
    eststo B_160
    local models `models' B_160
}
reghdfe car02 d size prior risk turn if base_ok, absorb(event_id) vce(cluster firm_id event_id)
eststo B_raw
local models `models' B_raw
esttab `models' using "$tables/baseline_robustness.csv", replace b(4) se(4) stats(N N_clust1 N_clust2) nostar

eststo clear
local models ""
foreach sig in z_median z90 ue {
    count if eps_ok & !missing(`sig')
    if r(N)>0 {
        gen double d_alt=d*`sig'
        reghdfe car02 d dz $controls if eps_ok & !missing(`sig'), absorb(event_id) vce(cluster firm_id event_id)
        eststo C_`sig'
        reghdfe car02 d d_alt $controls if eps_ok & !missing(`sig'), absorb(event_id) vce(cluster firm_id event_id)
        eststo S_`sig'
        local models `models' C_`sig' S_`sig'
        drop d_alt
    }
}
if "`models'"!="" esttab `models' using "$tables/eps_sensitivity.csv", replace b(4) se(4) stats(N N_clust1 N_clust2) nostar

gen byte h_only=customer_group==2 if linked
gen byte both=customer_group==3 if linked
gen double hz=h_only*z
gen double bz=both*z
count if eps_ok
if r(N)>0 {
    reghdfe car02 h_only both hz bz $controls if eps_ok, absorb(event_id) vce(cluster firm_id event_id)
    estimates store CustomerIdentity
    if _se[hz]>0 & _se[bz]>0 & !missing(_se[hz],_se[bz]) {
        lincom hz
        lincom bz
        lincom bz-hz
    }
    esttab CustomerIdentity using "$tables/customer_identity.csv", replace b(4) se(4) stats(N N_clust1 N_clust2) nostar
}

tempname leave
postfile `leave' int omitted_event double coefficient se p long n using "$tables/leave_one_event_out.dta", replace
local events ""
count if eps_ok
if r(N)>0 levelsof event_id if eps_ok, local(events)
foreach e of local events {
    capture noisily reghdfe car02 d dz $controls if eps_ok & event_id!=`e', absorb(event_id) vce(cluster firm_id event_id)
    if !_rc {
        if _se[dz]>0 & !missing(_se[dz]) {
            post `leave' (`e') (_b[dz]) (_se[dz]) (2*ttail(e(df_r),abs(_b[dz]/_se[dz]))) (e(N))
        }
        else {
            post `leave' (`e') (.) (.) (.) (e(N))
        }
    }
    else {
        post `leave' (`e') (.) (.) (.) (.)
    }
}
postclose `leave'
preserve
    use "$tables/leave_one_event_out.dta", clear
    write_csv using "$tables/leave_one_event_out.csv", replace
restore

use "$clean/weighted_panel.dta", clear
count if eps_ok & !missing(eh,es_customer,ehz,esz)
if r(N)>0 {
    egen byte firmtag=tag(firm_id) if eps_ok
    egen byte eventtag=tag(event_id) if eps_ok
    quietly count if firmtag==1
    local nf=r(N)
    quietly count if eventtag==1
    local ne=r(N)
    if `nf'>=10 & `ne'>=5 {
        reghdfe car02 d $controls if eps_ok, absorb(event_id) vce(cluster firm_id event_id)
        estimates store W_base
        reghdfe car02 eh es_customer ehz esz $controls if eps_ok, absorb(event_id) vce(cluster firm_id event_id)
        estimates store W_sales
        if _se[ehz]>0 & _se[esz]>0 & !missing(_se[ehz],_se[esz]) test ehz=esz
        esttab W_base W_sales using "$tables/customer_weights.csv", replace b(4) se(4) stats(N N_clust1 N_clust2) nostar
    }
    else {
        display "Weight coverage too sparse: report description only."
    }
    write_csv using "$audit/weight_sample_review.csv", replace
}
