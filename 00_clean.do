version 17.0
clear all
do "D:/ANU/s4/8100/ass/SY/code/00_config.do"
capture log close _all
log using "$logs/cleaning.log", text replace

do "$code/01_identity_retail.do"
do "$code/02_prices_sox.do"
do "$code/03_eps_signal.do"
do "$code/04_event_panel.do"
do "$code/04b_sample_selection.do"

display "Cleaning finished. Inspect $audit before interpreting the data."
log close
