version 17.0
global controls "size_w prior_w risk_w turn_w"

tempfile review
import delimited "$code/inputs/firm_event_review.csv", clear varnames(1) stringcols(_all) encoding("utf-8")
keep if stock_code!="" & event_id!=""
destring event_id link_public_verified confound_checked confound_flag, replace
isid stock_code event_id
foreach x in link_public_verified confound_checked confound_flag {
    assert inlist(`x',0,1) | missing(`x')
}
assert confound_checked==1 if !missing(confound_flag)
assert review_source!="" & firm_event_note!="" if link_public_verified==1 | confound_checked==1

gen byte link_full = ustrregexm(firm_event_note, "全部得到本次原文支持=1")
assert link_public_verified==1 if link_full==1

local core "매출액또는손익구조|잠정|단일판매ㆍ공급계약|유상증자|전환사채권발행결정|교환사채권발행결정|신주인수권부사채권발행결정|회사합병결정|회사분할결정|주식교환|출자증권양수결정|영업양수|매매거래정지|풍문또는보도"
gen byte confound_core = confound_flag==1 & ustrregexm(firm_event_note, "`core'")

tab link_public_verified link_full
tab confound_flag confound_core
keep stock_code event_id link_public_verified link_full confound_checked confound_flag confound_core
save `review'

use "$clean/regression_panel.dta", clear
merge 1:1 stock_code event_id using `review', generate(review_match)
assert review_match!=2
assert review_match==3 if base_ok==1
save "$clean/regression_panel_reviewed.dta", replace

gen byte r_noprelim   = prior_prelim==0
gen byte r_link_full  = link_full==1
gen byte r_news_core  = confound_core==0
gen byte r_link_any   = link_public_verified==1
gen byte r_news_broad = confound_flag==0

eststo clear
foreach r in noprelim link_full news_core link_any news_broad {
    reghdfe car02 d $controls if base_ok & r_`r', absorb(event_id) vce(cluster firm_id event_id)
    boottest d, cluster(firm_id event_id) bootcluster(event_id) weight(webb) reps($bootstrap_reps) seed(810017) nograph
    estadd scalar p_wild = r(p)
    eststo H1_`r'

    reghdfe car02 d dz $controls if eps_ok & r_`r', absorb(event_id) vce(cluster firm_id event_id)
    assert _se[dz]>0 & !missing(_se[dz])
    boottest dz, cluster(firm_id event_id) bootcluster(event_id) weight(webb) reps($bootstrap_reps) seed(810017) nograph
    estadd scalar p_wild = r(p)
    eststo H2_`r'
}

local mt `""No prelim." "Link strict" "News core" "Link any" "News broad""'
local opts replace b(4) se(4) nostar coeflabels(d "D (both customers)" dz "D x Z") ///
    stats(N N_clust1 N_clust2 p_wild, fmt(0 0 0 4) labels("Observations" "Firms" "Announcements" "Wild bootstrap p"))
esttab H1_* using "$tables/review_robustness_H1.csv", `opts' keep(d) mtitles(`mt')
esttab H1_* using "$tables/review_robustness_H1.rtf", `opts' keep(d) mtitles(`mt')
esttab H2_* using "$tables/review_robustness_H2.csv", `opts' keep(d dz) mtitles(`mt')
esttab H2_* using "$tables/review_robustness_H2.rtf", `opts' keep(d dz) mtitles(`mt')
esttab H1_*, b(4) se(4) keep(d) nostar stats(N N_clust1 N_clust2 p_wild)
esttab H2_*, b(4) se(4) keep(d dz) nostar stats(N N_clust1 N_clust2 p_wild)
display "REVIEW EXTENSIONS FINISHED"
