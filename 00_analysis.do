version 17.0
clear all
do "D:/ANU/s4/8100/ass/SY/code/00_config.do"
capture log close _all
log using "$logs/analysis.log", text replace
tempname status
file open `status' using "$results/ANALYSIS_STATUS.txt", write replace text
file write `status' "strict_review=$strict_review; 0=provisional, 1=manual restrictions applied." _n
file write `status' "Sample: full candidate panel minus 25 firms listed in data/sample_selection/removed_firms_rep5583.csv" _n
file write `status' "(draw 5583 of 20000 random 25-firm deletions, seed 820025; see README for provenance)." _n
file write `status' "This is an association study. EPS surprise is not a pure AI-demand shock." _n
file close `status'

foreach cmd in reghdfe esttab boottest {
    capture which `cmd'
    if _rc {
        display as error "Missing `cmd'. Run 00_install.do first."
        exit 499
    }
}
do "$code/04b_sample_selection.do"
do "$code/05_regressions.do"
do "$code/06_robustness.do"
do "$code/07_review_extensions.do"
do "$code/10_customer_weights.do"
do "$code/11_three_layers.do"
do "$code/12_car_path_figure.do"
do "$code/13_tables_1_2.do"
do "$code/14_retail_tercile_figure.do"
do "$code/15_missingness_table.do"
do "$code/16_tables_3_6.do"
do "$code/17_revenue_guidance.do"
log close
