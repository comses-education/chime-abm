;<<<<<<< HEAD
;;;-------DESCRIPTION OF PROCEDURES USED IN THIS AGENT-BASED-MODEL-----------------------------------------------------------------------------------
;Setup-Everything: Loads GIS files, loads hurricane best-track information, loads forecasts, sets the scale of the model world, generates the storm, and populates the model with agents (randomly distributed, based on population density, or based on census data). Assigns social networks to each citizen.
    ;1. Load-GIS: Displays the region of interest, loads GIS data (i.e., elevation; population density; counties; county¬¬ seats). Determines which patches are land and ocean. Ocean patches are designated where the elevation data has “no data” values.
    ;2. Load-Hurricane: Loads hurricane best track data. Defines a list called best-track-data that stores the best track data.
    ;3. Load-Forecasts: Loads full-worded forecast advisories from the National Hurricane Center and stores data in a list called forecast-matrix.
    ;4. Load-Forecasts-New: Loads a .csv file of forecast advisories and stores data in a list called forecast-matrix.
        ;1. Calculate-Advisory-Time: Converts times from the forecast advisory file to the date and hour.
        ;2. Calculate-Coordinates: Reports lat-lon coordinates of the storm center in model space.
    ;5. Setup: Sets the scale of the model world, generates the storm, and populates the model with agents (randomly distributed, based on population density, or based on census data). Assigns social networks to each citizen.
        ;1. Generate-Storm: Translates the best track data to the model grid and interpolates storm characteristics to 1-hourly data. Currently, brute-force interpolation is used to convert 6-hourly data to 1-hourly data. Draws a line that represents the actual track of the storm.
            ;1. Calculate-Time-Between-Storm-Info: Calculates the time interal between best track times.
        ;2. Create-Citizen-Agent-Population: Populates the model with citizens. Sets various attributes for each citizen (i.e., evac-zone, self-trust, trust-authority, networks lists, risk thresholds).
            ;1. Check-Zone: Determines the evacuation zone of each citizen, which depends on the number of grid points the citizen is away from the coast (i.e., zone “A” is 1.5 grid points from the coast).
        ;3. Create-Other-Agents: Populates the model with the various breeds of agents other than citizens (i.e., forecasters officials, broadcasters, and aggregators).
        ;4. Create-Citizen-Agents-From-Census-Tracts: Populates the model with citizens based on census data. Other agents (i.e., forecasters, officials, broadcasters, and aggregators) are populated similarly to create-agents.
            ;1. Create-More-Cit-Ags-Based-On-Census: Populates the model with more agents based on the census.
            ;2. Check-For-Swimmers: Moves citizens located at an ocean patch to a land patch.
            ;3. Add-Census-Factor: Set to true for each citizen that has the census information in their tract (e.g., kids under 18, adults over 65, limited English, use food stamps, no vehicle, no internet). This information is used in the decision-making process to calculate risk parameters.
        ;4;. Social-Network: Assigns a social network for each citizen. Each citizen is also assigned broadcasters and aggregators.


;Go: This procedure moves the hurricane in the Netlogo interface, forecasters publish new forecasts, broadcasters and aggregators update their forecast, citizens receive the updated forecast and produces a mental model of the storm, officials potentially issue evacuation orders, and citizens evaluate their risk to potentially make protective decisions.
    ;1. Move-Hurricane: Moves the hurricane symbol in the Netlogo interface.
    ;2. Past-Forecasts: Forecaster publishes the most recent forecast from forecast-matrix. A new forecast is published every 6 hours.
    ;3. Publish-New-Mental-Model: Each citizen has a mental model of where they think the hurricane will go and how severe it will be.
    ;4. Coastal-Patches-Alerts: Coastal patches diagnose if their patch is within an intensity threshold and distance threshold to issue an alert. If so, the patch communicates with the official to issue an alert.
    ;5. Issue-Alerts: The official issues an evacuation order after coastal-patches-alerts issues an alert.
    ;6. Decision-Module: The main Protective Action Decision-Making process called by citizen agents. Citizens check environmental cues, collect and process information, assess risk, assess alternative protective actions, and decide whether to act.
    ;7. Just-Collect-Info: Citizens who have already evacuated just collect information (no DM).

;Not called in code:
    ;1. Save-Individual-Cit-Ag-Evac-Records
    ;2. Save-Global-Evac-Statistics
    ;3. Save-View: Saves a .png of the Netlogo model space for each time step.

;Buttons but not called in the code:
    ;1. Show-Links: Creates lines that show which citizens are in which social network.


;; Declare netlogo extensions needed for the model
extensions [gis profiler csv nw]


;; Declare global variables
globals [
         clock                    ; keeps track of model time, same as ticks, but in days and hours
         county-seats             ; import dataset from GIS - county seats
         county-seat-list         ; list of county seats

         best-track-data              ; holds matrix of hurricane track/intensity/size etc
         hurricane-coords-best-track  ; holds x-y coordinates of the hurricane best track information in the model
         re0-0                    ; center of the Netlogo world used when translating real-world coordinates to model-space coordinates
         forecast-matrix          ; holds the most recent forecast generated by the Forecaster agent
         scale                    ; re-scales the modeled world to match the real world (n mi per degree)
         grid-cell-size           ; takes GIS world and converts grid cells to degrees

         tract-points             ; record the locations of census tracts
         using-hpc?               ; used to choose between two file paths one set is used when running the model on a HPC
         which-region?            ; determines which GIS files to load - was previously located in the GUI
         land-patches             ; patchset of land patches
         ocean-patches            ; patchset of ocean patches


         ; These variables need to be checked SMB*
         orang                    ; agentset for tracking evacuees in end-sim stats
         all                      ; agentset for tracking all cit-ags in end-sim stats
         really-affected          ; agentset for tracking affected cit-ags in end-sim stats
         data-dump                ; holds agent data when exporting the whole simulation
         output-filename
         evac-filename

         watching                 ; a single agent identified to track decisions
         risk-total               ; for display - to track watching's total risk
         risk-funct               ; for display - to track watching's risk function
         risk-error               ; for display - to track watching's risk error
         risk-orders              ; for display - to track watching's evacuation orders
         risk-env                 ; for display - to track watching's environmental cues
         risk-surge               ; for display - to track watching's surge risk
         ]

;; Declare agent breeds
breed [hurricanes hurricane]         ; hurricane, for display purposes only
breed [citizen-agents citizen-agent] ; citizen agents
breed [officials official]           ; public officials, emergency managers
breed [forecasters forecaster]       ; forecasters
breed [broadcasters broadcaster]     ; broadcasters
breed [aggregators aggregator]       ; aggregators
breed [forcstxs forcstx]             ; visualizes forecast cone/circles
breed [drawers drawer]               ; visualizes the forecast as a cone
breed [tracts tract]                 ; census tract points

;; Declare agent-specific variables
patches-own [
              density                   ; population density (from GIS)
              elev                   ; elevation (from GIS)
              county                 ; county
              alerts                 ; whether or not the county official has issued evacuation orders
              land?                  ; true or false variable for patches
             ]

hurricanes-own [  ]

citizen-agents-own [
         environmental-cues                ; environmental cues (based on distance from storm)
         evac-zone                         ; agent's perceived risk zone (based on distance from the coast)
         distance-to-storm-track

         decision-module-frequency         ; sets the frequency that agents run the risk-decision module
         previous-dm-frequency             ; agent remembers feedback1 in case of evacuation (reverts to original value)
         decision-module-turn              ; helps agents determine when it's their turn to run the risk-decision module

         my-network-list                   ; agent's social network (modified preferential attachment, see below)
         broadcaster-list                  ; the set of broadcasters linked to the agent
         aggregator-list                   ; the set of aggregators linked to the agent
         forecast-options                  ; list of forecasts available to the agent
         interpreted-forecast              ; an agent's interpretation of the forecast

         self-trust                        ; sets confidence in own interpretation of storm forecast
         memory                            ; holds the agent's intepretation of the forecast for use in next time through risk-decision loop
         trust-authority                   ; sets confidence in evac orders from officials  / SB 12.3.19 - this looks unused
         when-evac-1st-ordered             ; variable for recording when an evacuation is first ordered
         risk-watcher                      ; used in plotting risk

         risk-life                         ; characteristic sets threshold for determining risk to life
         risk-property                     ; characteristic sets threshold for determining risk to property
         info-up                           ; characteristic sets threshold for determining to collect more info (changes feedback1 loop)
         info-down                         ; characteristic sets threshold for determining to delay collecting more info (changes feedback1 loop)
         risk-estimate                     ; keeps a list of risk calculations
         completed                         ; keeps a list of previous decisons (and when they were made)
         risk-packet                       ; List the final risk, followed by the three main inputs to the risk function (forecast info, evac orders, env cues)

         ;;   Census Tract Information
         tract-information                 ; information from a census tract
         my-tract-population               ; population from census tract
         my-tract-household                ; total number of households from a census tract
         census-tract-number               ; number assigned to each census tract - assigned by the US government
         kids-under-18?                    ; records if the census tract has kids under 18
         adults-over-65?                   ; records if the census tract has adults over 65
         limited-english?                  ; records if the census tract has limited english speakers
         food-stamps?                      ; records if the census tract uses food stamps
         no-vehicle?                       ; records if the census tract does not have a vehicle
         no-internet?                      ; records if the census tract has access to interent

     ]

officials-own [
   orders                           ; keeps track of whether the official has issued evacuation orders
   distance-to-track                ; distance from the storm track (actual
   county-id                        ; sets the county of the official (from GIS)
   when-issued                      ; tracks when evacuation orders were issued
   ]

forecasters-own [current-forecast]  ; current forecast (set from the read-in historical forecasts, usually)
broadcasters-own [ broadcast ]      ; current broadcast (interpreted from the forecast)
aggregators-own [ info ]            ; current info (interpreted from the forecast, same as the broadcasters...)
forcstxs-own [ ]                    ;
drawers-own  [ cone-size ]          ; stores the cone size at the relevant hour (for drawing only)


  ;; MODEL PROCEDURES
  ;; Setup calls a handfull of other procedures to build the world and create the agents
  ;; Usually called from a button on the interface AFTER 1. loading the GIS, 2. loading the storm, and 3. loading the forecasts

to Setup
  __clear-all-and-reset-ticks

  ;;Load Geographic Data Used in the Simulation
  Load-GIS


  ;Where to have the legend displayed on the Netlogo interface
  let legend-location where-to-place-legend?  ;1=upper-right...2=upper-left...3=lower-left...4=lower-right
  if legend-location = "upper-right" [import-drawing "Legend/Legend_Upper_Right.png"]
  if legend-location = "upper-left"  [import-drawing "Legend/Legend_Upper_Left.png"]
  if legend-location = "lower-left" [import-drawing "Legend/Legend_Lower_Left.png"]
  if legend-location = "lower-right" [import-drawing "Legend/Legend_Lower_Right.png"]

  Load-Hurricane

  ;; *SMB We can change this once we finish redoing the forecasts
  ifelse which-storm? = "IRMA" or  which-storm? = "MICHAEL" [ Load-Forecasts-New ] [Load-Forecasts]


  set scale (item 0 grid-cell-size * 60.0405)  ;; THIS SHOULD BE the size of a grid cell in nautical miles, more or less ;; 60.0405 nm per degree

  Generate-Storm  ;; generates the hurricane

  set clock list item 3 item ticks hurricane-coords-best-track  item 4 item ticks hurricane-coords-best-track    ;; defines the clock

  ;; Setup Agents Based on if the Census Information is Being Used


  if use-census-data and which-region?  != "FLORIDA"
  [print "*** WARNING: Census Data is only available for Florida and will not be used for locations or decisions. ***"]

  ifelse use-census-data and which-region?  = "FLORIDA"
  [Create-Citizen-Agents-From-Census-Tracts];; creates agents based on census data and assigns them
  [Create-Citizen-Agent-Population];; creates the agents and distribtues them randomly or based on population density

  Create-Other-Agents;; Officials, Broadcasters and Aggregators are created

  Social-Network ;; defines the agents' social networks



   set risk-total 0        ;; these are all related to the risk function plot on the interface
   set risk-funct 0
   set risk-error 0
   set risk-orders 0
   set risk-env 0
   set risk-surge 0


end





to Go
  ; INFO:   The go procedure calls the various procedures that happen every time step in the model
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED:
  ; CALLED BY:

  ;;The hurricane moves to its historical location based on the time.
  ifelse using-hpc? [][Move-Hurricane]    ;; calls procedure to move the hurricane one time step - only show the visualization if using a local computer copy

  ;; update the forecast
  ask forecasters [  set current-forecast Past-Forecasts  ]


  let from-forecaster Publish-New-Mental-Model  ;; temporary variable to hold the interpreted version of the forecast (publish-new-mental-model is a reporter defined below)

  ;; officials take forecast info from broadcaster and generate an evacuation order code
  Coastal-Patches-Alerts
  ask officials with [any? land-patches with [county  = [[county] of patch-here] of myself]] [ Issue-Alerts ]

  ;; broadcasters translate and publish forecast
  ask broadcasters [ set broadcast from-forecaster ]

  ;; aggregators are like broadcasters, just translate and publish forecast (1/4 chance of running this code every time step)
  ask aggregators [ if random 3 = 2 [ set info from-forecaster] ]

  ;; cit-ags only run DM code when it's time, based on their internal schedule, and if they haven't evacuated already
  ask citizen-agents with [empty? completed or item 0 item 0 completed != "evacuate" ] [
         ifelse decision-module-turn < decision-module-frequency [ set decision-module-turn decision-module-turn + 1 ]
       [ set decision-module-turn 0
         Decision-Module ;; runs the decision model code
        ] ]

  ;;*** Why do what is mentioned below   SB **** JA: I am wondering the same...
  ;; UPDATE: 6/26/20 -  this bit of code doesn't actually happen - completed is a list so it never just equals completed
  ;; cit-ags who have evacuated revert back to original decision module frequency and only collect info (no DM
  ask citizen-agents with [completed = "evacuate" ] [
    print "It happened!"
         ifelse decision-module-turn < decision-module-frequency [ set decision-module-turn decision-module-turn + 1 ]
       [ set decision-module-turn 0
         Just-Collect-Info
        ] ]

  ask citizen-agents with [color = black] [set color blue]  ;; updates colors
  ask citizen-agents with [color = white] [set color blue]

  if ticks != 135 [ set clock list item 3 item ticks hurricane-coords-best-track  item 4 item ticks hurricane-coords-best-track  ]


  tick   ;; advances the model one time step

  if ticks = 135 [ stop ]


end


to Load-GIS
  ; INFO: Imports various GIS layers for use by the model
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED:
  ; CALLED BY:

     __clear-all-and-reset-ticks



    if which-storm? = "WILMA" or which-storm? = "WILMA_IDEAL" or which-storm? = "CHARLEY_REAL" or which-storm? = "CHARLEY_IDEAL" or which-storm? = "CHARLEY_BAD" or which-storm? = "IRMA" [set which-region? "FLORIDA"]
    if which-storm? = "HARVEY"  [set which-region? "GULF"]
    if which-storm? = "MICHAEL"  [set which-region? "GULF_AND_SE"]

     let elevation 0
     let density-map 0
     let counties 0
     if which-region? = "FLORIDA" [
      gis:load-coordinate-system "REGION/FLORIDA/GIS/block_density.prj"                  ; NetLogo needs a prj file to set up the conversion from GIS to netlogo grid
      set elevation gis:load-dataset "REGION/FLORIDA/GIS/Florida_SRTM_1215.asc"         ; Raster map - SRTM elevation data (downscaled using GRASS GIS)
      set density-map gis:load-dataset "REGION/FLORIDA/GIS/Pop_Density_1215.asc"            ; Raster map - Population density (calculated by census tract, modified for use w/ GRASS)
      set county-seat-list[]
      set county-seats gis:load-dataset "REGION/FLORIDA/GIS/county_seats.shp"           ; Vector map (points) - location of county seats
      set counties gis:load-dataset "REGION/FLORIDA/GIS/counties_1.asc"                 ; Raster map - counties
       foreach but-last gis:feature-list-of county-seats [ ?1 ->
        set county-seat-list lput list gis:property-value ?1 "CAT" (gis:location-of (first (first (gis:vertex-lists-of ?1)))) county-seat-list
       ]]
     if which-region? = "GULF" [
     gis:load-coordinate-system "REGION/GULF/GIS/block_density.prj"                                  ; NetLogo needs a prj file to set up the conversion from GIS to netlogo grid
      set elevation gis:load-dataset "REGION/GULF/GIS/gulf_states_extended.asc"                      ; Raster map - SRTM elevation data (downscaled using GRASS GIS)
      set density-map gis:load-dataset "REGION/GULF/GIS/gulf_states_pop_density_extended.asc"            ; Raster map - Population density (calculated by census tract, modified for use w/ GRASS)
      set county-seat-list []
      set county-seats gis:load-dataset "REGION/GULF/GIS/gulf_states_county_seats.shp"           ; Vector map (points) - location of county seats
      set counties gis:load-dataset "REGION/GULF/GIS/gulf_states_counties_extended.asc"                 ; Raster map - counties
       foreach but-last gis:feature-list-of county-seats [ ?1 ->
        set county-seat-list lput list gis:property-value ?1 "CAT" (gis:location-of (first (first (gis:vertex-lists-of ?1)))) county-seat-list
     ]]

      if which-region? = "GULF_AND_SE" [
      set elevation gis:load-dataset "REGION/GULF_SE/GIS/elevation_reduced_by2.asc"         ; Raster map - SRTM elevation data (downscaled by a factor of 2 using QGIS)
      gis:set-world-envelope-ds gis:envelope-of elevation
      set density-map gis:load-dataset "REGION/GULF_SE/GIS/pop_density.asc"                     ; Raster map - Population density (calculated by census tract (downscaled by a factor of 3 using QGIS)
      set county-seat-list []
      set counties gis:load-dataset "REGION/GULF_SE/GIS/counties_lowres4.asc"               ; Raster map - counties (downscaled by a factor of 4 using QGIS)
      set county-seats gis:load-dataset "REGION/GULF_SE/GIS/county_centroid_clipped.shp"    ; Vector map (points) - location of county centers (not county seats)
      foreach but-last gis:feature-list-of county-seats [ ?1 ->
      set county-seat-list lput list gis:property-value ?1 "OBJECTID" (gis:location-of (first (first (gis:vertex-lists-of ?1)))) county-seat-list ;;;county_seat_list is a list: [county_seat_number [x and y points of county seats in Netlogo world]]
      ]]


     gis:set-world-envelope-ds gis:envelope-of elevation

     let world gis:world-envelope
     let degree-x abs (item 1 world - item 0 world) / (2 * max-pxcor)   ;; sets grid cell size in degrees
     let degree-y abs (item 3 world - item 2 world) / (2 * max-pycor)

     set grid-cell-size list degree-x degree-y  ;; holds x and y grid cell size in degrees
     set re0-0 list (((item 0 world - item 1 world) / 2) + item 1 world) (((item 2 world - item 3 world) / 2) + item 3 world)
     file-close-all

   gis:apply-raster elevation elev
   gis:apply-raster density-map density
   gis:apply-raster counties county
   gis:paint elevation 0 ;; the painted raster does not necessarily correspond to the elevation
   ask patches [set land? true]
   ;ask patches with [not (dens >= 0 or dens <= 0)] [set pcolor 102 set land? false]
   ask patches with [not (elev >= 0 or elev <= 0)] [set pcolor 102 set land? false]

   set land-patches patches with [land? = true]
   set ocean-patches patches with [land? = false]
   set using-hpc? false

end

to Load-Hurricane
  ; INFO: Loads hurricane best track data from a text or csv file. Defines a list called "best-track-data" that stores the best track data (sublists exist for each time of best track data).
  ; VARIABLES MODIFIED: "best-track-data" contains best track data in the format for each time: [status of system,lat,lon,intensity,pressure,date,hour,radii (4 quadrants) of 34-kt winds, radii (4 quadrants) of 64-kt winds]
  ; PROCEDURES CALLED: None
  ; CALLED BY: Setup-Everything

  ; Best track data is every 6 hours in the format: [date,hour,identifier,status of system,lat,lon,wind speed,pressure,34-kt wind radii in quadrants (NE,SE,SW,NW), radii of 50 kt winds, radii of 64 kt winds]
  ; Here is a description of the best track format: https://www.nhc.noaa.gov/data/hurdat/hurdat2-format-nov2019.pdf
  let storm-file "" ; storm-file is set to the directory and file that contains the best track information.
    if which-storm? = "HARVEY" [ set storm-file "STORMS/HARVEY/HARVEY.txt" ]
    if which-storm? = "WILMA" [ set storm-file "STORMS/WILMA/WILMA_NEW.csv" ]
    if which-storm? = "WILMA_IDEAL" [set storm-file "STORMS/WILMA_IDEAL/WILMA_NEW.csv" ]
    if which-storm? = "CHARLEY_REAL" [ set storm-file "STORMS/CHARLEY_REAL/CHARLEY.txt" ]
    if which-storm? = "CHARLEY_IDEAL" [ set storm-file "STORMS/CHARLEY_IDEAL/CHARLEY.txt" ]
    if which-storm? = "CHARLEY_BAD" [ set storm-file "STORMS/CHARLEY_BAD/CHARLEY.txt" ]
    if which-storm? = "IRMA" [ set storm-file "STORMS/IRMA/IRMA.txt" ]
    if which-storm? = "DORIAN" [ set storm-file "STORMS/DORIAN/DORIAN.txt" ]
    if which-storm? = "MICHAEL" [ set storm-file "STORMS/MICHAEL/AL142018_best_track_cut.txt" ]

  file-open storm-file  ; imports the best track data

  ; This code block parses the text/csv file and places the best track information in a "hurricane-file" list. Each new line of the best track data is appended, resulting in one big list.
  ; Example of hurricane-file: [20181006, 1800,  , LO, 17.8N,  86.6W,  25, 1006,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0, 20181007, 0000,.....]
  let hurricane-file []
  while [ not file-at-end? ]
    [ set hurricane-file sentence hurricane-file file-read-line ]
  file-close


  let Tparsed "" ; "Tparsed" is an individual string from the list "hurricane-file"
  let parsed []  ; "parsed" is a list that combines all of the strings in "hurricane-file", but with commas removed
  let all-parsed [] ; "all-parsed" is a list with data for each best track time, with commas removed, and sublists for each time
  foreach hurricane-file [ ?1 -> ; "?1" represents each line in "hurricane-file"
     let i 0
   while [i < length ?1] [
     set Tparsed word Tparsed item i ?1 ; "Tparsed" is set to a value in "hurricane-file". Once a comma is found, the comma is removed and "Tparsed" is reset
     if item i ?1 = "," [ set parsed lput remove "," Tparsed parsed ; Removes commas from "Tparsed". "parsed" is in format: [20181006  1800     LO  17.8N   86.6W   25  1006     0     0     0     0     0     0     0     0     0     0     0     0]
                         set Tparsed ""
                         ]
              set i i + 1 ]
     set all-parsed lput parsed all-parsed ; Adds the list "parsed" to the end of the list "all_parsed". "all_parsed" is a list with sublists for each best track time.
     set parsed [] ]

; This line makes sure the best track first time is AT or AFTER the first time of the forecast advisories (so the forecast starts at or before the best track data).
; Example of the issue: For Hurricane Michael, advisories (starting at 2100 UTC) would start after the best track time (starting at 1800 UTC), which means the forecast does not cover the first best track time.

  set all-parsed but-first all-parsed
  set best-track-data map [ ?1 -> (list item 3 ?1 but-last item 4 ?1 replace-item 1 but-last item 5 ?1 ;Re-orders the data in "all-parsed". "replace-item" adds a negative sign to lon, and "but-last" removes the "N" and "W" from the lat-lon coordinates in the best track file.
      "-" item 6 ?1 item 7 ?1 item 0 ?1  item 1 ?1 item 8 ?1 item 9 ?1 item 10 ?1 item 11 ?1 item 16 ?1
      item 17 ?1 item 18 ?1 item 19 ?1) ] all-parsed  ;"best-track-data" is a list of best track data with a sublist for each time. Each sublist is: [status of system,lat,lon,intensity,pressure,date,hour,radii (4 quadrants) of 34-kt winds, radii (4 quadrants) of 64-kt winds]

end


to Load-Forecasts

  ; INFO: Load hurricane forecast information based on the hurricane selected in the interface
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED:
  ; CALLED BY:


   set forecast-matrix []

   let storm-file ""
    if which-storm? = "HARVEY" [ set storm-file "STORMS/HARVEY/HARVEY ADVISORIES.txt" ]
    if which-storm? = "WILMA" [ set storm-file "STORMS/WILMA/WILMA ADVISORIES.txt" ]              ;; defines the correct list of advisories from pull-down menu
    if which-storm? = "WILMA_IDEAL" [set storm-file "STORMS/WILMA_IDEAL/FAKE_WILMA ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_REAL" [ set storm-file "STORMS/CHARLEY_REAL/CHARLEY ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_IDEAL" [ set storm-file "STORMS/CHARLEY_IDEAL/CHARLEY_IDEAL ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_BAD" [set storm-file "STORMS/CHARLEY_BAD/BAD_FAKE_CHARLEY ADVISORIES.txt" ]
    if which-storm? = "IRMA" [ set storm-file "STORMS/IRMA/IRMA ADVISORIES.txt" ]
    if which-storm? = "DORIAN" [ set storm-file "STORMS/DORIAN/DORIAN ADVISORIES.txt" ]

 let file-list []

 ;; the storm-file is a list of all the advisories, which are stored as separate text files directly from NOAA/NHC website
 ;; this index file is parsed and then each of the advisories is parsed for relevant forecast information

 file-open storm-file

 while [not file-at-end?] [ set file-list lput file-read-line file-list] ;; transfer the list of advisories to a netlogo list
 file-close

 foreach file-list [ ?1 -> ;; Open each of the files located in "Storm"_advisories
 file-open ?1
  let forecast-file []

  while [ not file-at-end? ]
    [
      set forecast-file sentence forecast-file word file-read-line " "
    ]
  file-close

  let Tparsed ""
  let parsed []
  let all_parsed []

;; The advisory parser is fairly complicated... because the advisories themselves are much more than a simple rectangular data file...

  foreach forecast-file [ ??1 ->
     let i 0
   while [i < length ??1 ] [
     set Tparsed word Tparsed item i ??1
     if item i ??1 = " " [ set parsed lput remove " " Tparsed parsed
                         set Tparsed ""
                         ]
              set i i + 1
      ]
     set all_parsed lput parsed all_parsed
     set parsed []
    ]


  let s-line remove "" item 4 all_parsed
  let schedule list read-from-string item 3 s-line read-from-string but-last item 0 s-line


  let forecasts filter [ ??1 -> length ??1 > 2 and item 1 ??1 = "VALID" ]  all_parsed
  set forecasts map [ ??1 -> remove "" ??1 ] forecasts


  while [length item 2 last forecasts > 10 and substring item 2 last forecasts (length item 2 last forecasts - 5)  (length item 2 last forecasts - 0)  = "ORBED"] [set forecasts but-last forecasts]
  let winds but-first filter [ ??1 -> length ??1 > 2 and item 0 ??1 = "MAX" ]  all_parsed
  while [length winds < length forecasts] [ set winds (sentence winds "")]


  set winds map [ ??1 -> remove "" ??1 ] winds

  let dia64 map [ ??1 -> remove "" ??1 ] filter [ ??1 -> item 0 ??1 = "64" ] all_parsed
  let dia34 map [ ??1 -> remove "" ??1 ] filter [ ??1 -> item 0 ??1 = "34" ] all_parsed

 let dia34-list []
 if not empty? dia34 [
 set dia34-list map [ ??1 -> map [ ???1 -> read-from-string ???1 ] but-first map [ ???1 -> but-last but-last ???1 ] remove "" map [ ???1 -> remove "KT" remove "." ???1 ]  ??1 ] dia34
 set dia34-list but-first dia34-list ]
 while [length dia34-list < length forecasts] [
 set dia34-list (sentence dia34-list "") ]



 let dia64-list []
 if not empty? dia64 [
 set dia64-list map [ ??1 -> map [ ???1 -> read-from-string ???1 ] but-first map [ ???1 -> but-last but-last ???1 ] remove "" map [ ???1 -> remove "KT" remove "." ???1 ]  ??1 ] dia64
 set dia64-list but-first dia64-list ]
 while [length dia64-list < length forecasts] [
 set dia64-list (sentence dia64-list "") ]




  set forecast-matrix lput fput schedule (map [ [??1 ??2 ??3 ??4] -> (sentence
                   read-from-string substring item 2 ??1  0 position "/" item 2 ??1
                   read-from-string substring item 2 ??1 (position "/" item 2 ??1 + 1) position "Z" item 2 ??1
                  (( read-from-string substring item 3 ??1 0 4 - item 1 re0-0) / item 1 grid-cell-size)  ; lat
                  (((-1 * read-from-string substring item 4 ??1 0 4) - item 0 re0-0) / item 0 grid-cell-size)  ; lon
                   read-from-string item 2 ??2 ; wind max
                   (list ??3) (list ??4) ) ; wind dia34 (NE SE SW NW) and dia64 (NE SE SW NW)
      ]
                forecasts winds dia34-list dia64-list) forecast-matrix



  ]
 ;print "final forecast:"
 ;show forecast-matrix

 file-close-all

end

to Load-Forecasts-New
  ; INFO: Load hurricane forecast information based on the hurricane selected in the interface
  ; VARIABLES MODIFIED: The main variable modified is the forecast-matrix. The forecasts include historical predictions about the storm based on the amount of time before the storm hits
  ; PROCEDURES CALLED: Calculate-Advisory-Time is called and used to convert forecast times that are saved in forecast-matrix
  ; CALLED BY: Setup

   set forecast-matrix [] ; This is the main variable that will be modified in this procedure and records forecasts that will be used throughout the simulation

   let storm-file "" ; The storm file is a csv that is read and parsed into the forecast-matrix
    if which-storm? = "HARVEY" [ set storm-file "STORMS/HARVEY/HARVEY ADVISORIES.txt" ]
    if which-storm? = "WILMA" [ set storm-file "STORMS/WILMA/WILMA ADVISORIES.txt" ]
    if which-storm? = "WILMA_IDEAL" [set storm-file "STORMS/WILMA_IDEAL/FAKE_WILMA ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_REAL" [ set storm-file "STORMS/CHARLEY_REAL/CHARLEY ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_IDEAL" [ set storm-file "STORMS/CHARLEY_IDEAL/CHARLEY_IDEAL ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_BAD" [set storm-file "STORMS/CHARLEY_BAD/BAD_FAKE_CHARLEY ADVISORIES.txt" ]
    if which-storm? = "IRMA" [ set storm-file "STORMS/IRMA/IRMA_ADVISORIES.csv" ]
    if which-storm? = "DORIAN" [ set storm-file "STORMS/DORIAN/DORIAN ADVISORIES.txt" ]
    if which-storm? = "MICHAEL" [ set storm-file "STORMS/MICHAEL/perfect_forecast.csv" ]

   let all-advisories csv:from-file storm-file

  ;; If it needs to be added later, a similar batch of code to that below could be used to sort for ofcl forecasts

   let advisories-parsed []; the first list used to hold information from the first parsing of all-advisories

   ;; First filter out rows that are NOT used which have a time and pressure of 0 and save them in advisories-parsed
   foreach all-advisories [ this-advisory ->
    let this-forecast-time item 5 this-advisory
    let pressure-value item 9 this-advisory
    ifelse this-forecast-time = 0 and pressure-value = 0 [][
    set advisories-parsed lput this-advisory advisories-parsed
    ]
   ]
  let forecast-time 0
  let all-forecasts [] ;; the new list that holds the parsed information
  let unique-advisory [] ;; a sub list that is saved to the all-forecasts list


  ;; This next section of code below is to move each row into a new list entry by date to replicate the previous format
  ;; This results in a list which contains a list of all information for each day in one row
  ;; Previous Format:  [ [Day 1 Time 1]
  ;;                   [Day 1 Time 2]
  ;;                   [Day 2 Time 1]
  ;;                   [Day 2 Time 2]]
  ;;  New Format:      [[Day 1 Time 1 Time 2]
  ;;                   [Day 2 Time 1 Time 2]]

  foreach advisories-parsed [this-advisory ->

    ; same forecast time - so keep adding it to the list for that day
    ifelse forecast-time = (item 2 this-advisory) [
      set unique-advisory  lput this-advisory unique-advisory
    ]
    ; Each unique forecast is added to its own list called unique-advisory. When a new forecast time is detected, that sub-list is added to the list of all information, all-forecasts
    ;new forecast time
    [
      if forecast-time != 0 [set all-forecasts lput unique-advisory all-forecasts]
      set forecast-time item 2 this-advisory
      set unique-advisory []
      set unique-advisory  lput this-advisory unique-advisory

    ]
  ]
  ;; all-forecasts now contatins the partially parsed information that has each forecast time recorded as its own sublist

  set forecast-time 0
  let entries-for-one-day []
  let entries-for-all-days []

  ; Now parse each day into one entry that follows the format used to load previous information
  ; The format contains different types of information within sub-lists as shown below:
  ;          [Date of Forecast [ individual forecast time, netlogo coordinates, max wind [wind 34] [wind 64] ]
  ; EXAMPLE: [5 1200 [5 1800 -198.23361282214213 470.7438061089692 155 [130 100 80 110] [40 35 30 35]]]
  foreach all-forecasts [whole-advisory-day ->

    let first-entry item 0 whole-advisory-day
    let date item 2 first-entry
    let hours-away item 5 first-entry ; used to id the current time for this list entry
    let schedule Calculate-Advisory-Time date hours-away
    set entries-for-one-day []
    set entries-for-one-day lput schedule entries-for-one-day  ;; uses a reporter that update the time correctly

    let entries-for-one-time-on-one-day []
    let list-34 []
    let list-64 []
    let new-time-entry false
    let first-entry-from-this-advisory true
    let current-forecast-time 0

    ; This section goes through each forecast entry for a unique forecast time and parses the information
    foreach whole-advisory-day [ this-advisory ->

      ;; we don't save the forecast info that is currently occuring - just future ones, so get rid of a few
      let entry-hours-away item 5 this-advisory

      if entry-hours-away != hours-away[
        ; set wind-speed
        let wind-speed item 11 this-advisory

        ; check to see if its a new time
        ifelse current-forecast-time != (item 5 this-advisory) and first-entry-from-this-advisory = false [
           set new-time-entry true
        ][set new-time-entry false
          set first-entry-from-this-advisory false]

        ifelse new-time-entry[
          ; save the info and reset lists to 0

          ifelse length list-34 > 0 [set schedule lput list-34 schedule]
          [let empty (word list-34 "")
            set schedule lput empty schedule]
          ifelse length list-64 > 0 [set schedule lput list-64 schedule]
          [
            let empty (word list-64 "")
            set schedule lput empty schedule]

          set entries-for-one-day lput schedule entries-for-one-day

          set current-forecast-time item 5 this-advisory
          set entries-for-one-time-on-one-day []
          set list-34 []
          set list-64 []


          ; save current info
          set date item 2 this-advisory
          let this-hours-away item 5 this-advisory ; used to id the current time
          set schedule Calculate-Advisory-Time date this-hours-away
          ;;[5 1800 -198.23361282214213 470.7438061089692 155 [130 100 80 110] [40 35 30 35]]
          ;; add the coordinates and the max windspeed to schedule

          let coords Calculate-Coordinates  item 7 this-advisory item 6 this-advisory

          set schedule lput item 1 coords schedule
          set schedule lput item 0 coords schedule
          set schedule lput item 8 this-advisory schedule

          ;set schedule
          ;save windspeed list
          if wind-speed = 34[
            set list-34 lput item 13 this-advisory list-34
            set list-34 lput item 14 this-advisory list-34
            set list-34 lput item 15 this-advisory list-34
            set list-34 lput item 16 this-advisory list-34

          ]
          if wind-speed = 64[
            set list-64 lput item 13 this-advisory list-64
            set list-64 lput item 14 this-advisory list-64
            set list-64 lput item 15 this-advisory list-64
            set list-64 lput item 16 this-advisory list-64
          ]

        ][ ; Repeat the same steps as above, this is for a different time from the same forecast

          ; save current info
          ;save windspeed list
          set date item 2 this-advisory
          let this-hours-away item 5 this-advisory ; used to id the current time
          set schedule Calculate-Advisory-Time date this-hours-away
          ;; General format:  [5 1800 -198.23361282214213 470.7438061089692 155 [130 100 80 110] [40 35 30 35]]
          ;; add the coordinates and the max windspeed to schedule
          let coords Calculate-Coordinates  item 7 this-advisory item 6 this-advisory
          set schedule lput item 1 coords schedule
          set schedule lput item 0 coords schedule
          set schedule lput item 8 this-advisory schedule


          if wind-speed = 34[
            set list-34 lput item 13 this-advisory list-34
            set list-34 lput item 14 this-advisory list-34
            set list-34 lput item 15 this-advisory list-34
            set list-34 lput item 16 this-advisory list-34
          ]
          if wind-speed = 64[
            set list-64 lput item 13 this-advisory list-64
            set list-64 lput item 14 this-advisory list-64
            set list-64 lput item 15 this-advisory list-64
            set list-64 lput item 16 this-advisory list-64
          ]
          set current-forecast-time item 5 this-advisory
        ]
      ]
    ]
        ; save the last forecast time from each day here:
        ifelse length list-34 > 0 [set schedule lput list-34 schedule]
          [let empty (word list-34 "")
            set schedule lput empty schedule]
        ifelse length list-64 > 0 [set schedule lput list-64 schedule]
          [
            let empty (word list-64 "")
            set schedule lput empty schedule]

          set entries-for-one-day lput schedule entries-for-one-day


         set entries-for-all-days lput entries-for-one-day entries-for-all-days
  ]

; The parsing is complete and the forecast-matrix is set
; The format is as follows:
  ; [Date of Forecast [ individual forecast time, netlogo coordinates, max wind [wind 34] [wind 64]] [[ individual forecast time, netlogo coordinates, max wind [wind 34] [wind 64]] ...]
  ; [Date of Forecast [ individual forecast time, netlogo coordinates, max wind [wind 34] [wind 64]] [[ individual forecast time, netlogo coordinates, max wind [wind 34] [wind 64]] ...]

  set forecast-matrix  entries-for-all-days


end

to-report Calculate-Advisory-Time [time hours-away]
  ; INFO:    This procedure translates times from the file to the date and the hour.
  ;           2017090506 6    ->  5 1200
  ; VARIABLES MODIFIED: Converts the time and hours away to a different format - see above line
  ; PROCEDURES CALLED: Its used when the forecast info is parsed during the setup of the model.
  ; CALLED BY: Load-Forecast

  ;JA: What happens if the month changes for a storm? - SB - The immediate effect is an extra day. We could try and prevent this - but I'm waiting till we get to past-forecast so that I can understand how these forecasts are read
  let advisory-time[]
  let time-word (word time)
  ;parse the individual numbers from the incoming variable time
  let day substring time-word 6 8
  let hour substring time-word 8 10
  set day read-from-string day
  set hour read-from-string hour
  set hour hour + hours-away

  if hour > 23 [ ;  adjust the date of a forecast to account for periods of time greater than 24 hours
   let days-to-add 0
   let hours-past-0 hour
    while [hours-past-0 > 23] [
       set days-to-add days-to-add + 1
       set hours-past-0 hours-past-0 - 24
    ]
    set day day + days-to-add
    set hour hours-past-0
  ]
  set hour hour * 100 ; to make 12, look like 1200 etc.
  ; report a two entry list that contains the parsed day and hour
  set advisory-time lput day advisory-time
  set advisory-time lput hour advisory-time

  report advisory-time

end


to-report Calculate-Coordinates [long lat]
  ; INFO: Covert latitude and longitude coordinates to Netlogo world coordinates
  ; VARIABLES MODIFIED: long and lat to long-coord and lat-coord
  ; PROCEDURES CALLED: None
  ; CALLED BY: Load-Forecasts-New


  let lat-coord  but-last lat
  let long-coord but-last long
  set lat-coord  read-from-string lat-coord
  set long-coord  read-from-string long-coord

  ; for some reason there are no decimal places in the incoming coordinates that should be there... e.g. 577 should be 57.7

  let coordinates []
  set lat-coord lat-coord / 10
  set long-coord -1 * (long-coord / 10)

  ; the math that converts coordinates from lat/long to netlogo
  set lat-coord (lat-coord - item 1 re0-0) / (item 1 grid-cell-size) ; lat
  set long-coord (long-coord - item 0 re0-0) / (item 0 grid-cell-size)  ; lon

  set coordinates lput long-coord coordinates
  set coordinates lput lat-coord coordinates


  report coordinates
end


to Generate-Storm
  ; INFO: Translates the best track data and interpolates its characteristics for the in-between hours
  ; VARIABLES MODIFIED: modifies best-track-data and creates hurricane-coords-best-track which is used to draw the hurricane
  ; PROCEDURES CALLED
  ; CALLED BY: SETUP


   let re-scaled best-track-data

   ;; first the hurricane_info array is re-worked to model-space coordinates and strings converted to numbers. Values are intially saved as strings when read from text files
   ;; Lat/Long coordinates are converted to Netlogo coordinates
   ;; The hour is extracted from the time stamp
   ;; For Example:
   ;; [[ LO  18.1  -86.9   25  1004 20181007  0000     0     0     0     0     0     0     0     0] ......
   ;; [[ LO -215.33360000140334 -32.462238805294746 25 1004 7 0 0 0 0 0 0 0 0 0]

      set re-scaled map  [ ?1 -> (list item 0 ?1 (( read-from-string item 1 ?1  - item 1 re0-0) / item 1 grid-cell-size )
           ((read-from-string item 2 ?1 - item 0 re0-0) / item 0 grid-cell-size ) read-from-string item 3 ?1
           read-from-string item 4 ?1 (read-from-string word last but-last item 5 ?1 last item 5 ?1) read-from-string item 6 ?1
                                read-from-string item 7 ?1 read-from-string item 8 ?1 read-from-string item 9 ?1
                                read-from-string item 10 ?1 read-from-string item 11 ?1 read-from-string item 12 ?1 read-from-string item 13 ?1
                                read-from-string item 14 ?1)  ]   re-scaled


   ;; Temporary variables used in the calculation of interpoloated storm characteristics
   let t-y 0
   let t-x 0
   let t-z 0
   let t-34-ne 0
   let t-34-se 0
   let t-34-sw 0
   let t-34-nw 0
   let t-64-ne 0
   let t-64-se 0
   let t-64-sw 0
   let t-64-nw 0
   let day item 5 item 0 re-scaled
   let hour item 6 item 0 re-scaled
   let i 1
   set hurricane-coords-best-track  [] ; the list that will contain the newly interpolated storm location information

   ;; the following is basically brute-force interpoloation. The code marches through the array of storm info
   ;; and takes the difference from one best track time to the next, then calculates the interpolated points
   ;; It does this for all of the dozen or so characteristics of the storm at each point
   ;; We assume that the difference between each storm info is less than a day (e.g., most best track data is supplied every 6 hours)
   ;;For best track data that does not follow the same temporal format as the rest of the data (e.g., data is every 6 hours, but landfall is at 5.3 hours), delete the lines that do not follow the same temporal format

   while [i < length re-scaled] [

      set t-y item 1 item i re-scaled - item 1 item (i - 1) re-scaled
      set t-x item 2 item i re-scaled - item 2 item (i - 1) re-scaled
      set t-z item 3 item i re-scaled - item 3 item (i - 1) re-scaled
      set t-34-ne item 7 item i re-scaled - item 7 item (i - 1) re-scaled
      set t-34-se item 8 item i re-scaled - item 8 item (i - 1) re-scaled
      set t-34-sw item 9 item i re-scaled - item 9 item (i - 1) re-scaled
      set t-34-nw item 10 item i re-scaled - item 10 item (i - 1) re-scaled
      set t-64-ne item 11 item i re-scaled - item 11 item (i - 1) re-scaled
      set t-64-se item 12 item i re-scaled - item 12 item (i - 1) re-scaled
      set t-64-sw item 13 item i re-scaled - item 13 item (i - 1) re-scaled
      set t-64-nw item 14 item i re-scaled - item 14 item (i - 1) re-scaled
      set day item 5 item (i - 1) re-scaled
      set hour item 6 item (i - 1) re-scaled
      let hour2 item 6 item i re-scaled
      let hours-between-storm-info Calculate-Time-Between-Storm-Info hour hour2

    ; variables that record the newlyy interpolated storm location information
      let new-y []
      let new-x []
      let new-z []
      let new-34-ne []
      let new-34-se []
      let new-34-sw []
      let new-34-nw []
      let new-64-ne []
      let new-64-se []
      let new-64-sw []
      let new-64-nw []
      let new-day []
      let new-hour []
      let j 0  ; used to track which 1/6 of the interpolation is being calculated
        repeat hours-between-storm-info [set new-y lput ((j * (t-y / hours-between-storm-info)) + item 1 item (i - 1) re-scaled) new-y
                  set new-x lput ((j * (t-x / hours-between-storm-info)) + item 2 item (i - 1) re-scaled) new-x
                  set new-z lput ((j * (t-z / hours-between-storm-info)) + item 3 item (i - 1) re-scaled) new-z
                  set new-34-ne lput ((j * (t-34-ne / hours-between-storm-info)) + item 7 item (i - 1) re-scaled) new-34-ne
                  set new-34-se lput ((j * (t-34-se / hours-between-storm-info)) + item 8 item (i - 1) re-scaled) new-34-se
                  set new-34-sw lput ((j * (t-34-sw / hours-between-storm-info)) + item 9 item (i - 1) re-scaled) new-34-sw
                  set new-34-nw lput ((j * (t-34-nw / hours-between-storm-info)) + item 10 item (i - 1) re-scaled) new-34-nw
                  set new-64-ne lput ((j * (t-64-ne / hours-between-storm-info)) + item 11 item (i - 1) re-scaled) new-64-ne
                  set new-64-se lput ((j * (t-64-se / hours-between-storm-info)) + item 12 item (i - 1) re-scaled) new-64-se
                  set new-64-sw lput ((j * (t-64-sw / hours-between-storm-info)) + item 13 item (i - 1) re-scaled) new-64-sw
                  set new-64-nw lput ((j * (t-64-nw / hours-between-storm-info)) + item 14 item (i - 1) re-scaled) new-64-nw
                  set new-day lput day new-day
                  set new-hour lput ((100 * j) + hour) new-hour
                  set j j + 1]

      (foreach new-y new-x new-z new-day new-hour new-34-ne new-34-se new-34-sw new-34-nw new-64-ne new-64-se new-64-sw new-64-nw
      [ [?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?10 ?11 ?12 ?13] -> set hurricane-coords-best-track  lput (list ?2 ?1 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?10 ?11 ?12 ?13 ) hurricane-coords-best-track  ])
      set i i + 1
   ]

  ; Now all of the coordinates are rounded to two decimal places
  ; EX: [[-32.462238805294746 -215.33360000140334 25 7 0 0 0 0 0 0 0 0 0] .....
  ; ->  [[-32.46 -215.33 25 7 0 0 0 0 0 0 0 0 0] .....
   set hurricane-coords-best-track  map [ ?1 -> map [ ??1 -> precision  ??1 2 ] ?1 ] hurricane-coords-best-track


  ;; Now drawer agents are used to create a storm track path across the screen. Then links are made between the agents.
  ;; This results in a gray line that shows the storm path across the screen.
  ;; These agents are not used in the evacuation simulation.

   foreach hurricane-coords-best-track [ ?1 -> if (item 0 ?1 > min-pxcor and item 0 ?1 < max-pxcor and
                           item 1 ?1 > min-pycor and item 1 ?1 < max-pycor)  [
         create-drawers 1 [set size 0.1
                           setxy item 0 ?1 item 1 ?1]
         ] ]
    let draw-line turtle-set drawers with [size = 0.1]
      set i 0
    while [i < (length sort draw-line - 1)] [
      ask item i sort draw-line [create-link-to item (i + 1) sort draw-line ]
      set i i + 1 ]

end

to-report Calculate-Time-Between-Storm-Info [ time1 time2 ]
  ; INFO: Calculates the time interval between best track times.
  ; VARIABLES MODIFIED: time-difference-best-track
  ; PROCEDURES CALLED: None
  ; CALLED BY: Generate-Storm

  ; numbers are stored as 600 and 1200 - so you have to divide by 100
  let time-difference-best-track (time2 - time1) / 100
  ; if the time is the next day then a negative number results so we have to calculate things to account for that
  if time-difference-best-track < 0 [
    set time-difference-best-track 24 - (time1 / 100)
    set time-difference-best-track time-difference-best-track + (time2 / 100)
  ]
  report time-difference-best-track
end


to Create-Citizen-Agent-Population
  ; INFO: Creates citizen agents
  ; VARIABLES MODIFIED: Citizens aquire values for their variables (e.g., location, trust thresholds, risk thresholds).
  ; PROCEDURES CALLED: Check-Zone
  ; CALLED BY: Setup


  set-default-shape citizen-agents "circle"
  let tickets sort [density] of patches with [density > 0] ;Sorts patches that have a population density greater than zero. "tickets" is a list storing each population density value.
  let ranked-patches sort-on [density] patches with [density > 0] ;"ranked-patches" is a list storing the location of each patch with population density greater than zero.
  let sum_T sum tickets ;"sum_T" is the entire population of the domain.

  ;Creates agents and sets the size of the circle displayed on the Netlogo interface
  create-citizen-agents #citizen-agents [
    set color blue
    set size 1

   ;distribute_population=true means citizens are placed based on population distribution. distribute_population=false means citizens are placed randomly.
    ifelse distribute_population [
    ;This is the way population is distributed based on population density. A random values is chosen ("lotto") between 0 and the sum_T. Then, a while loop runs until i is greater than lotto.
    ;A citizen is placed on the patch where i>=lotto. This process naturally separates citizens based on population density, because a more populous patch has a greater chance of the random number (lotto) in it's range, and thus, a citizen on a more populous patch.
    let lotto random-float sum_T
    let i 0
    let j 0
    while [i < lotto] [
       set i i + item j tickets
       set j j + 1 ]
    move-to item (j - 1) ranked-patches ]
   [move-to one-of patches with [density >= 0 ] ;citizen is placed randomly on a patch with a population density greater than zero.

   if which-storm? = "MICHAEL" [ ;Josh added this hard-coded information for hurricane Michael to increase the sample size of citizens near the coast in Michael's path.
       let landfall_lat 30.0
       let landfall_lon -85.5
       let landfall_lon_netlogo_world (landfall_lon - item 0 re0-0)/ item 0 grid-cell-size
       let landfall_lat_netlogo_world (landfall_lat - item 1 re0-0)/ item 1 grid-cell-size
       let distance-citizens 40
       move-to one-of patches with [(density >= 0) and (pycor < landfall_lat_netlogo_world + distance-citizens) and (pycor >  landfall_lat_netlogo_world - distance-citizens) and (pxcor < landfall_lon_netlogo_world + distance-citizens) and (pxcor >  landfall_lon_netlogo_world - distance-citizens)]
       let coast-distance [distance myself] of min-one-of ocean-patches  [distance myself]
        while[coast-distance >= 6] [ ;Keep moving citizens until they are, at most, 6 grid points from the coast.
        move-to one-of patches with [(density >= 0) and (pycor < landfall_lat_netlogo_world + distance-citizens) and (pycor >  landfall_lat_netlogo_world - distance-citizens) and (pxcor < landfall_lon_netlogo_world + distance-citizens) and (pxcor >  landfall_lon_netlogo_world - distance-citizens)]
        set coast-distance [distance myself] of min-one-of ocean-patches  [distance myself]
   ]]

   ]

    ;These two lines spread out citizens slightly so they are not in the same place or in straight lines.
    set heading random 360
    fd random-float .5

    set evac-zone Check-Zone ;Each citizen runs "Check-Zone" prodedure to determine which evacuation zone they are in.
    set self-trust .6 + random-float .4 ;citizens set their self-trust
    set trust-authority random-float 1 ;citizens set their trust in authorities
    set forecast-options [ ]
    set my-network-list [ ]
    set broadcaster-list [ ]
    set aggregator-list  [ ]
    set interpreted-forecast []
    set memory list self-trust interpreted-forecast ;"memory" includes a citizen's self trust and interpreted forecast

  ;; for new decision model, citizens determine risk perception thresolds
    set risk-life random-normal 14 2 ;Random number chosen from a distribution with a mean of 14 and a standard deviation of 2
    set risk-property random-normal (.7 * risk-life) .5 ;"risk-property" depends on "risk-life"
      if risk-property > risk-life [set risk-property risk-life] ;"risk-property" cannot be greater than "risk-life". A citizen should not have a higher risk threshold for property compared to their life.
    set info-up random-normal (.4 * risk-life) .5 ;"info-up" depends on "risk-life". If "risk-life" is greater, a citizen would collect information later.
      if info-up > risk-property [set info-up risk-property] ;A citizen should collect information before their "risk-property" threshold is reached.
    set info-down random-normal (.1 * risk-life) .5
      if info-down > info-up [set info-down info-up - .1] ;The threshold for collecting less information should be lower than collecting more infomation.

    ;Zero out risk properties if they are less than zero.
    if risk-life < 0 [set risk-life 0]
    if risk-property < 0 [set risk-property 0]
    if info-up < 0 [set info-up 0]
    if info-down < 0 [set info-down 0]

  ;; other citizen variables
    set risk-estimate [0] ;List of risk calculations
    set environmental-cues  0
    set decision-module-frequency round random-normal 12 2 ;Sets the frequency that agents run the risk-decision module
    set previous-dm-frequency decision-module-frequency
    set decision-module-turn random 10 ;Helps agents determine when it's their turn to run the risk-decision module
    set completed []
    set distance-to-storm-track 99

    set risk-packet (list item 0 risk-estimate environmental-cues  0 0) ;List the final risk, followed by the three main inputs to the risk function (forecast info, evac orders, env cues)
    ]

end

to-report Check-Zone
  ; INFO:  Used to determine which zone an agent is located in.
  ; VARIABLES MODIFIED: zn (evacuation zone; either "A", "B", or "C")
  ; PROCEDURES CALLED: None
  ; CALLED BY: Create-Citizen-Agent-Population; Create-Citizen-Agents-From-Census-Tracts

  let zn ""

  ;Each citizen determines what evacuation zone they are in, depending on how far away they are from the coast. Random error in a citizen's knowledge is added. Roughly 20% of the time, a citizen will randomly choose an evacuation zone, which may be an inaccurate zone for their location.
  ifelse random-float 1 < .8 [
    let dist-coast [distance myself] of min-one-of ocean-patches  [distance myself]
    if dist-coast <= 1.5 [set zn "A"]
    if dist-coast > 1.5 and dist-coast <= 3 [set zn "B"]
    if dist-coast > 3 and dist-coast <= 5 [set zn "C"]
   ]
   [ set zn one-of ["A" "B" "C" ""] ]
  report zn ;
end

to  Create-Other-Agents
  ; INFO: Create agents that are used to spread information. This includes forecasters, officials, aggregators and broadcasters. Forecasters, officials, broadcasters, and aggregators are placed on the Netlogo interface.
  ; VARIABLES MODIFIED: Some variables associated with each agent is assigned.
  ; PROCEDURES CALLED: None
  ; CALLED BY: Setup

  let tickets sort [density] of patches with [density > 0] ;Sorts patches that have a population density greater than zero. Tickets is a list storing each population density value.
  let ranked-patches sort-on [density] patches with [density > 0] ;"ranked-patches" is a list storing the location of each patch with population density greater than zero.
  let sum_T sum tickets ;"sum_T" is the entire population of the domain.

  set-default-shape forecasters "circle"
  create-forecasters 1 [ ;There is one forecaster
    set color green
    set size 1
    let lotto random-float sum_T ;The next lines places the forecaster at a location based on population density
    let i 0
    let j 0
    while [i < lotto] [
       set i i + item j tickets
       set j j + 1
     ]
    move-to item (j - 1) ranked-patches
    set current-forecast Past-Forecasts ;Past-Forecasts is the advisory data
    ]


  set-default-shape officials "star"
  foreach county-seat-list [ ?1 ->
  create-officials 1 [
    set color red
    set size 1.5
    set xcor item 0 item 1 ?1 ;Official is placed at the location given in the county-seat-list data
    set ycor item 1 item 1 ?1
    set orders 0
    set distance-to-track 99
    set county-id item 0 ?1
    ]
  ]

  set-default-shape broadcasters "circle"
  create-broadcasters #broadcasters [
    set color yellow
    set size .5
    let lotto random-float sum_T ;The next lines places the broadcasters at a location based on population density
    let i 0
    let j 0
    while [i < lotto] [
       set i i + item j tickets
       set j j + 1
     ]
    move-to item (j - 1) ranked-patches
    set broadcast []
    ]


  set-default-shape aggregators "circle"
  create-aggregators #net-aggregators [
    set color pink
    set size .5
    let lotto random-float sum_T ;The next lines places the broadcasters at a location based on population density
    let i 0
    let j 0
    while [i < lotto] [
       set i i + item j tickets
       set j j + 1
     ]
     move-to item (j - 1) ranked-patches
    set info []
    ]


  set-default-shape hurricanes "storm"

end

;Census tract definition: Small, relatively permanent statistical subdivisions of a county. Census tracts average about 4000 people (minimum of 1200; maximum of 8000 people)
to Create-Citizen-Agents-From-Census-Tracts
  ; INFO: Create citizens based on census information. More citizens are created if the tract population is at least two times greater than a ratio set by a user button (citizen-to-census-population-ratio).
  ; VARIABLES MODIFIED: New citizens are created based on census tract data.
  ; PROCEDURES CALLED: Create-More-Cit-Ags-Based-On-Census; Check-For-Swimmers; Add-Census-Factor
  ; CALLED BY: Setup

  let tractfile "flcensusdata/fltractpoint5.shp" ;This data works for only the Florida domain

  set tract-points gis:load-dataset tractfile ;Load census data, which consists of many variables (see sitefields for a list of variables)
  let sitefields gis:property-names tract-points ;Name of tract data: [CAT STATE_FIPS CNTY_FIPS STCOFIPS TRACT FIPS POPULATION POP_SQMI POP2010 POP10_SQMI AGE_UNDER5 AGE_5_9 AGE_10_14 AGE_15_19 AGE_20_24 AGE_25_34 AGE_35_44 AGE_45_54 AGE_55_64 AGE_65_74 AGE_75_84 AGE_85_UP MED_AGE MED_AGE_M MED_AGE_F HOUSEHOLDS AVE_HH_SZ HSEHLD_1_M HSEHLD_1_F MARHH_CHD MARHH_NO_C MHH_CHILD FHH_CHILD FAMILIES AVE_FAM_SZ HSE_UNITS VACANT OWNER_OCC RENTER_OCC SQMI SHAPE_LENG SHAPE_AREA LONGITUDE LATITUDE TOTAL_HH HH_WUNDR18 HH_WOVER65 HHWOVR65_1 HHWOVR65_2 LMTED_ENG HHUSEFSTMP OVR60FDSTM HH_WDISABI HH_WDISAFS HH_WCOMPUT HHNOINTERN HNOINT20K HNOINT20_7 HOVR65NOCO HH_NOVEHIC EDLESSHS NOWRK12M]
  let feature-list gis:feature-list-of tract-points ;Contains the value for each sitefields. Each point is represented by its own feature list.
  set-default-shape citizen-agents "circle"

  foreach feature-list [ ?1 ->  ;Go through each feature list (each census tract point)
    ;; create a census tract agent for each GIS vector point
    let sitepoint gis:centroid-of ?1 ;Reports a single Vertex representing the centroid (center of gravity) of the given feature
    let prop-list []
    let this-feature ?1
    foreach sitefields [ ??1 -> ;; iterate through all of the data that corresponsds to each site and make a list that will be handed off to agents
      let prop-field gis:property-value this-feature ??1 ;Returns the value of each feature in the tract point
      set prop-list lput prop-field prop-list ;Puts the values of each feature into a list. This list contains all of the tract infomration for each point.
    ]

    let location gis:location-of sitepoint ;Reports a two-element list containing the x and y values (in that order) of the given vertex translated into NetLogo world space using the current transformation
    ifelse empty? location [
    print "ERROR: Tract data has missing values"
    ][
    create-citizen-agents 1 [ ;; initialize an agent to represent a tract in the simulation
      setxy item 0 location item 1 location ;Sets the citizen location in Netlogo space
      set color blue
      set size 1
      ;; new cit-ag info
      set tract-information prop-list ;tract-information may look like the following, which lists all of the tract information for a point: [39 12 091 12091 022600 12091022600 3408 3550 3053 3180.2 222 169 143 145 280 574 316 454 301 210 166 73 34.9 32.8 38.5 1449 2 319 341 111 207 36 186 621 2.84 1748 299 387 1062 0.96 0.06979775537 2.3394793E-4 -86.6094201866 30.4076438608 1672 381 367 255 112 38 352 81 410 197 1331 539 183 318 117 180 80 0.171651495]
      set my-tract-population item 6 tract-information ;sets the population of a given tract point
      set my-tract-household item 44 tract-information ;sets the number of total households in the tract
      set census-tract-number item 5 tract-information ;sets the unique tract number

      ;; original citizen information (as used above)
      set evac-zone Check-Zone ;Each citizen runs "Check-Zone" prodedure to determine which evacuation zone they are in.
      set self-trust   .6 + random-float .4 ;citizens set their self-trust
      set trust-authority random-float 1 ;citizens set their trust in authorities
      set forecast-options [ ]
      set my-network-list [ ]
      set broadcaster-list [ ]
      set aggregator-list  [ ]
      set interpreted-forecast []
      set memory list self-trust interpreted-forecast ;"memory" includes a citizen's self trust and interpreted forecast

      ;; for new decision model, citizens determine risk perception thresolds
      set risk-life random-normal 14 2 ;Random number chosen from a distribution with a mean of 14 and a standard deviation of 2
      set risk-property random-normal (.7 * risk-life) .5 ;"risk-property" depends on "risk-life"
        if risk-property > risk-life [set risk-property risk-life] ;"risk-property" cannot be greater than "risk-life". A citizen should not have a higher risk threshold for property compared to their life.
      set info-up random-normal (.4 * risk-life) .5 ;"info-up" depends on "risk-life". If "risk-life" is greater, a citizen would collect information later.
        if info-up > risk-property [set info-up risk-property] ;A citizen should collect information before their "risk-property" threshold is reached.
      set info-down random-normal (.1 * risk-life) .5
        if info-down > info-up [set info-down info-up - .1] ;The threshold for collecting less information should be lower than collecting more infomation.

      ;Zero out risk properties if they are less than zero.
      if risk-life < 0 [set risk-life 0]
      if risk-property < 0 [set risk-property 0]
      if info-up < 0 [set info-up 0]
      if info-down < 0 [set info-down 0]

      ;; other citizen variables
      set risk-estimate [0] ;List of risk calculations
      set environmental-cues  0
      set decision-module-frequency round random-normal 12 2 ;Sets the frequency that agents run the risk-decision module
      set previous-dm-frequency decision-module-frequency
      set decision-module-turn random 10 ;Helps agents determine when it's their turn to run the risk-decision module
      set completed []
      set distance-to-storm-track 99
      set risk-packet (list item 0 risk-estimate environmental-cues  0 0) ;List the final risk, followed by the three main inputs to the risk function (forecast info, evac orders, env cues)

    ]
  ]
  ]

  ;Create more agents based on the census numbers
  ask citizen-agents [Create-More-Cit-Ags-Based-On-Census]

  ;; Make sure there are no agents in the water
  ask citizen-agents [Check-For-Swimmers]

  ifelse kids-under-18-factor [ask citizen-agents [set kids-under-18? Add-Census-Factor 45]] [ask citizen-agents [set kids-under-18? false]] ;If user button is "On", then "kids-under-18-factor" is set to true. There is randomness such that "kids-under-18-factor" is sometimes not set equal to true (see Add-Census_Factor).
  ifelse adults-over-65-factor [ask citizen-agents [set adults-over-65? Add-Census-Factor 46]] [ask citizen-agents [set adults-over-65? false]]
  ifelse limited-english-factor [ask citizen-agents [set limited-english? Add-Census-Factor 49]] [ask citizen-agents [set limited-english? false]]
  ifelse use-food-stamps-factor [ask citizen-agents [set food-stamps? Add-Census-Factor 50]] [ask citizen-agents [set food-stamps? false]]
  ifelse no-vehicle-factor [ask citizen-agents [set no-vehicle? Add-Census-Factor 59]] [ask citizen-agents [set no-vehicle? false]]
  ifelse no-internet-factor [ask citizen-agents [set no-internet? Add-Census-Factor 55]] [ask citizen-agents [set no-internet? false]]
end

to Create-More-Cit-Ags-Based-On-Census
  ; INFO: Used to create more citizens if a census tract has a large population. The user sets citizen-to-census-population-ratio. If the tract population is at least two times greater than this ratio, at least one more citizen will be created.
  ; VARIABLES MODIFIED: Creates more citizens. New citizens obtain their "parent" information, except randomly-assinged variables (e.g., risk information) are re-assigned to the new citizen.
  ; PROCEDURES CALLED: None
  ; CALLED BY: Create-Citizen-Agents-From-Census-Tracts


  if my-tract-population < 1 [
    die
    print "Problematic tract information - census tract reported no people"
  ] ;; get rid of any problematic citizen agents

  let citizens-to-make round (my-tract-population / citizen-to-census-population-ratio) ;User sets citizen-to-census-population-ratio (a button). If the tract population is at least double this ratio, then more citizens will be created for that tract point.

  if citizens-to-make >= 2[ ;make sure you need to make more citizens since one is already made
     hatch-citizen-agents (citizens-to-make - 1) [ ;Creates "citizens-to-make - 1" new citizens
      ;; this command means that all of the information from the parent is inherited, so only values that need to be randomized are modified below
      set self-trust   .6 + random-float .4 ;citizens set their self-trust
      set trust-authority random-float 1 ;citizens set their trust in authorities
      set forecast-options [ ]
      set my-network-list [ ]
      set broadcaster-list [ ]
      set aggregator-list  [ ]
      set interpreted-forecast []
      set memory list self-trust interpreted-forecast

      ;; for new decision model
      set risk-life random-normal 14 2 ;Random number chosen from a distribution with a mean of 14 and a standard deviation of 2
      set risk-property random-normal (.7 * risk-life) .5 ;"risk-property" depends on "risk-life"
        if risk-property > risk-life [set risk-property risk-life] ;"risk-property" cannot be greater than "risk-life". A citizen should not have a higher risk threshold for property compared to their life.
      set info-up random-normal (.4 * risk-life) .5 ;"info-up" depends on "risk-life". If "risk-life" is greater, a citizen would collect information later.
        if info-up > risk-property [set info-up risk-property] ;A citizen should collect information before their "risk-property" threshold is reached.
      set info-down random-normal (.1 * risk-life) .5
        if info-down > info-up [set info-down info-up - .1] ;The threshold for collecting less information should be lower than collecting more infomation.

      ;Zero out risk properties if they are less than zero.
      if risk-life < 0 [set risk-life 0]
      if risk-property < 0 [set risk-property 0]
      if info-up < 0 [set info-up 0]
      if info-down < 0 [set info-down 0]

      ;; other citizen variables
      set risk-estimate [0] ;List of risk calculations
      set environmental-cues  0
      set decision-module-frequency round random-normal 12 2 ;Sets the frequency that agents run the risk-decision module
      set previous-dm-frequency decision-module-frequency
      set decision-module-turn random 10 ;Helps agents determine when it's their turn to run the risk-decision module
      set completed []
      set distance-to-storm-track 99
      set risk-packet (list item 0 risk-estimate environmental-cues  0 0) ;List the final risk, followed by the three main inputs to the risk function (forecast info, evac orders, env cues)

    ]
 ]

end

to Check-For-Swimmers
  ; INFO: Moves citizens that are located in the water to nearby land. This situation can occur when an agent is in a coastal location that was both land and water in one projection, but is labeled water when reprojected in Netlogo.
  ; VARIABLES MODIFIED: None. This procedure simply moves citizens.
  ; PROCEDURES CALLED: None
  ; CALLED BY: Create-Citizen-Agents-From-Census-Tracts

  let this-patch-is-land [land?] of patch-here ;"this-patch-is-land"=true if the patch is land
  if not this-patch-is-land [ ;If the partch a citizen is on is currently a water patch, move the citizen to the closest land patch.
     let nearby-patch min-one-of land-patches [distance myself] ;Finds the nearest land-patch
     ifelse nearby-patch != nobody [move-to nearby-patch] ;If a land patch is found, the citizen moves to that land patch.
     [die] ;The citizen dies if it does not have a nearby land patch.
  ]
end


to-report Add-Census-Factor [x]
  ; INFO: Reads census information from a given column number and uses the number of people with that characteristic to determine the likelhood that an agent will also have that characteristic.
  ; VARIABLES MODIFIED: is_factor?
  ; PROCEDURES CALLED: None
  ; CALLED BY: Create-Citizen-Agents-From-Census-Tracts

        let is-factor? false
        let factor-from-census item x tract-information ;"factor-from-census" is the value of the specific tract data (e.g., how many kids under 18).
        if  factor-from-census != 0 [ ;If the value is greater than zero, continue
        let factor-likelihood  (factor-from-census /  my-tract-household) * 100 ;Sets "factor-likelihood" as the ratio between the number of households in the census compared the number of households in the tract (e.g., "2 households with kids under 18" per household).
        ifelse   factor-likelihood  >= ((random 99) + 1) ;Random generator to determine if is-factor? is set to true. It is set to true if "factor-likelihood" is greater than a random number between 0 and 100.
          [set is-factor?  true] [set is-factor? false]
      ]
  report is-factor?
end


to Social-Network
  ; INFO:  Creates the networks used by citizen agents to make decisions and gather forecast information
  ; VARIABLES MODIFIED: The variables my-network-list broadcaster-list and aggregator-list
  ; PROCEDURES CALLED: None
  ; CALLED BY: Setup after all of the agents have been created

 ;; uses a simple routine to create a scale-free network
  ;SB change network size name
  ;SB describe the lists
  let net-power network-size   ; network-size is set in the user interface
  ask citizen-agents [

    let nearby-agents citizen-agents with [distance myself < network-distance] ; network-distance is set in the user interface and a maximum distance to choose agents from
    let partner nobody

        if any? nearby-agents [
              ; chooses a random maximum number of agents to add to the network list
              ; since each agent runs this code in succession, the length of my-network-list starts out at 0 and increases
              let total-agents-needed random-float sum [length my-network-list ^ net-power] of nearby-agents

              ; if both the original agent and the agent that is nearby need an agent to fill their network list, then make a link between the two of them
              ask nearby-agents [
              let nc length my-network-list ^ net-power
                   if partner = nobody [
                        ifelse nc > total-agents-needed
                        [ set partner self
                          set my-network-list lput myself my-network-list ]
                        [ set total-agents-needed total-agents-needed - nc ]
                    ]
              ]
        ]
       if partner = nobody [set partner one-of citizen-agents with [distance myself < (network-distance + network-distance)] ]
       set my-network-list lput partner my-network-list
    ]

   ask citizen-agents [ set my-network-list remove nobody my-network-list ] ; if there are agent sets with nobody recorded - get rid of that entry

 ;; hooks up some triads in the network, creating greater density
   ask citizen-agents [
     let new-link nobody
     let net-list turtle-set my-network-list
       ask one-of net-list [
         let T-net-list turtle-set my-network-list
         set new-link one-of T-net-list
         if new-link = nobody [ set new-link one-of citizen-agents with [distance myself < network-distance ] ]
       ]
        ask new-link [ set my-network-list lput myself my-network-list ]
        set my-network-list lput new-link my-network-list
       ]

 ;; cleans up each agent's network list by removing duplicates and connections to itself
  ask citizen-agents [
       set my-network-list sort remove-duplicates my-network-list
       set my-network-list remove self my-network-list

      ; adds random trust-factor -  since the order of links determines the trust
       set my-network-list sort-by [ [?1 ?2] -> item 1 ?1 > item 1 ?2 ] map [ ?1 -> list ?1 random-float 1 ] my-network-list
  ]

  ;;my-network-list now contains a list of agents and a trust factor associated with each agent
  ;; For example: [[(citizen-agent 3603) 0.6855141520445518] [(citizen-agent 2751) 0.2831065466947966] [(citizen-agent 572) 0.26522023914016035] [(citizen-agent 3138) 0.2623628848068422]]

 ;; creates media preferences (broadcasters & aggretators) for the agents  (adds trust factor)  -  since the order of links determines the trust
  ask citizen-agents [
       set broadcaster-list sort-by [ [?1 ?2] -> item 1 ?1 > item 1 ?2 ] map [ ?1 -> list ?1 random-float 1 ] sort n-of random count broadcasters broadcasters
       set aggregator-list  sort-by [ [?1 ?2] -> item 1 ?1 > item 1 ?2 ] map [ ?1 -> list ?1 random-float 1 ] sort n-of random count aggregators aggregators
  ]

end



to Move-Hurricane
  ; INFO: Moves a visualization of the hurricane across the screen to locations recorded in the list hurricane-coords-best-track
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED: None
  ; CALLED BY:  GO

        let hx round item 0 item ticks hurricane-coords-best-track
        let hy round item 1 item ticks hurricane-coords-best-track

        ;; only move the hurricane when it is within the boundaries of the world (create the hurricane if there isn't one already)
           if not any? hurricanes and any? patches with [pxcor = hx and pycor = hy]  [
              create-hurricanes 1 [
                set size 2 * max (list item 5 item ticks hurricane-coords-best-track item 6 item ticks hurricane-coords-best-track item 7 item ticks hurricane-coords-best-track item 8 item ticks hurricane-coords-best-track) / scale
                set color white
                set label-color red
                set label item 2 item ticks hurricane-coords-best-track ] ]

        ;; if the hurricane passes off the map, delete it
           if any? hurricanes and not any? patches with [pxcor = hx and pycor = hy] [ ask hurricanes [die] ]

        ;; while the hurricane is within the map, set coordinates and other characteristics based on the hurricane-coords-best-track array
           if any? hurricanes [
             ask last sort hurricanes [
                set size 2 * max (list item 5 item ticks hurricane-coords-best-track item 6 item ticks hurricane-coords-best-track item 7 item ticks hurricane-coords-best-track item 8 item ticks hurricane-coords-best-track) / scale
                setxy hx hy
                set heading heading - 14] ]


  ;; next section simply updates the info box on the current state of the storm that is shown in the visualization
     let intense ""
     if item 2 item ticks hurricane-coords-best-track < 34 [ set intense "TD" ]
     if item 2 item ticks hurricane-coords-best-track >= 34 and item 2 item ticks hurricane-coords-best-track < 64 [ set intense "TS" ]
     if item 2 item ticks hurricane-coords-best-track >= 64 and item 2 item ticks hurricane-coords-best-track < 83 [ set intense "H1" ]
     if item 2 item ticks hurricane-coords-best-track >= 83 and item 2 item ticks hurricane-coords-best-track < 96 [ set intense "H2" ]
     if item 2 item ticks hurricane-coords-best-track >= 96 and item 2 item ticks hurricane-coords-best-track < 113 [ set intense "MH3" ]
     if item 2 item ticks hurricane-coords-best-track >= 113 and item 2 item ticks hurricane-coords-best-track < 137 [ set intense "MH4" ]
     if item 2 item ticks hurricane-coords-best-track >= 137 [ set intense "MH5" ]
     ask hurricanes [ set label intense]

end

to-report Past-Forecasts
  ; INFO: Method for the forecaster to publish a forecast modeled on the 5-day cone product from the NHC
  ; forecast location and severity of the storm is set for 12 24 36 48 72 96 120 hrs from current location of the storm
  ; a location for 120 hrs is selected using a stripped down version of the NHC data for 2009-2013,
  ; meaning that 2/3 of the STORMS fall within the 226 n mi error, while 1/3 have a larger error.
  ; a random heading and distance for that error is selected
  ; the heading stays the same for the closer forecasts, but distance is adjusted per the NHC 2009-2013 data.
  ; the n mi is standardized to 226 n mi = 5 grid cells... adjust with s-f_real (scale-factor) and related variables below
  ; the reported generates a list of the six forecasts, which is published every 6 hours and available to the intermediate agents.
  ; if the later forecast(s) are off the edge of the world, they are not shown/reported.
  ; thin black circles show the current forecast on the display
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY: Create-Other-Agents; Go


   let forecast_list []
   ask forcstxs [die]
   let s-f 0
   let s-f_real (357 / scale )
   let error_list [] ;  cone of uncertainty
  ;SB add in interpolation for hourly 0-12 is 0-26 (nautical miles)  - maybe not actual nautical miles
  ; SB - convert degreees to nautical miles?
   ifelse which-storm? = "IRMA" [ set error_list [26 43 56 74 103 151 198]] [set error_list [44 77 111 143 208 266 357]]
   if which-storm? = "MICHAEL" [ set error_list [26 43 56 74 103 151 198 198 198]] ; SB this is probably wrong - The error list is specific to each storm. Not sure why these are created or if they are still needed with the new readi in procedures
                                                                                  ; JA: I think they are still needed and are associated with the cone of uncertainty in the model. error_list has 7 numbers, representing 12h, 24h, 36h, 48h, 72h, 96h, and 120h forecasts. Not sure exactly how these numbers were obtained (do not agree with National Hurricane Center values). I just added two extra numbers because my Michael forecast has forecasts out to 168 h. I think ultimately, it would be nice to have hourly error data directly related to the input forecast time intervals. Note that current NHC error data only goes out to 120 hours, so we could extrapolate the error from 120 to 168 hrs, if the input forecast data has forecasts out to that time range (like Hurricane Michael and many other more recent hurricanes).
  while [length error_list > length forecast-matrix] [set error_list but-last error_list]
   let severity_list []
   let size_list []
   let time_list []
   let new-forecast last filter [ ?1 -> item 0 item 0 ?1 < item 0 clock or (item 0 item 0 ?1 = item 0 clock and item 1 item 0 ?1 < item 1 clock) ] forecast-matrix ;Makes sure the advisory data begins at or before the best track time

  let current_F but-first new-forecast

  while [length error_list > length current_F] [set error_list but-last error_list ]

   let winds34 map [ ?1 -> ifelse-value (?1 = "") [[]] [?1] ] map [ ?1 -> item 5 ?1 ] current_F

   let winds64 map [ ?1 -> ifelse-value (?1 = "") [[]] [?1] ] map [ ?1 -> item 6 ?1 ] current_F

   set time_list map [ ?1 -> list item 0 ?1 item 1 ?1 ] current_F

   set forecast_list map [ ?1 -> list item 3 ?1 item 2 ?1 ] current_F

   set severity_list map [ ?1 -> item 4 ?1 ] current_F

   set size_list map [ ?1 -> ?1 ] error_list

   let published_forc []

   set published_forc (map [ [?1 ?2 ?3 ?4 ?5 ?6] -> (list ?1 ?2 ?3 ?4 ?5 ?6) ] severity_list forecast_list size_list time_list winds34 winds64)

  report published_forc

end


to-report Publish-New-Mental-Model
  ; INFO: Main method for the various agents to publish a "mental model" of where they think the hurricane will go and how severe it will be
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY:

  let long-list []
  let t_Forc [current-forecast] of one-of forecasters


    let current-storm (list
      item 2 item ticks hurricane-coords-best-track
      list item 0 item ticks hurricane-coords-best-track item 1 item ticks hurricane-coords-best-track
      1
      list item 3 item ticks hurricane-coords-best-track item 4 item ticks hurricane-coords-best-track
      (list item 5 item ticks hurricane-coords-best-track item 6 item ticks hurricane-coords-best-track item 7 item ticks hurricane-coords-best-track item 8 item ticks hurricane-coords-best-track)
      (list item 9 item ticks hurricane-coords-best-track item 10 item ticks hurricane-coords-best-track item 11 item ticks hurricane-coords-best-track item 12 item ticks hurricane-coords-best-track))

    set t_Forc fput current-storm t_Forc


 ; Is the cone being modified in here
  let i 0
  while [i < length t_Forc - 1] [
    let first-two list item i t_Forc item (i + 1) t_Forc
    let interpolated []
;    show first-two
    let j 0
    let lim 0
      let d1 item 0 item 3 item 0 first-two
      let d2 item 0 item 3 item 1 first-two
      let h1 item 1 item 3 item 0 first-two
      let h2 item 1 item 3 item 1 first-two

     while [d1 < d2] [set h1 h1 + 100
                      set lim lim + 1
                      if h1 = 2400 [set d1 d1 + 1 set h1 0] ]
     while [h1 < h2] [set h1 h1 + 100
                      set lim lim + 1 ]

    if lim != 0 [
    let Delt_wind (item 0 item 1 first-two - item 0 item 0 first-two) / lim
    let Delt_x (item 0 item 1 item 1 first-two - item 0 item 1 item 0 first-two) / lim
    let Delt_y (item 1 item 1 item 1 first-two - item 1 item 1 item 0 first-two) / lim
    let Delt_err (item 2 item 1 first-two - item 2 item 0 first-two) / lim

    let clk item 3 item 0 first-two

    while [j < (lim )] [
     ifelse item 1 clk < 2300 [ set clk replace-item 1 clk (item 1 clk + 100) ] [set clk list (item 0 clk + 1) 0]
     set interpolated lput (list ((j * Delt_wind) + item 0 item 0 first-two)
                              list ((j * Delt_x) + item 0 item 1 item 0 first-two) ((j * Delt_y) + item 1 item 1 item 0 first-two)
                              ((j * Delt_err) + item 2 item 0 first-two)
                              clk)
                                 interpolated
     set j j + 1

   ]
    set long-list sentence long-list interpolated
  ]
    set i i + 1
    ]

  set long-list filter [ ?1 -> item 0 item 1 ?1 > min-pxcor and item 0 item 1 ?1 < max-pxcor and item 1 item 1 ?1 > min-pycor and item 1 item 1 ?1 < max-pycor ] long-list
  set long-list remove-duplicates long-list


  ;; for display of forecast track:
     let color-code 65
     ask drawers with [size = .05 or size = .02 or size = .03] [die]
     foreach long-list [ ?1 ->
         create-drawers 1 [
                 setxy item 0 item 1 ?1 item 1 item 1 ?1
                 set size .05
                 if item 0 ?1 >= 64 and item 0 ?1 < 82 [set color-code 67]
                 if item 0 ?1 >= 82 and item 0 ?1 < 95 [set color-code 47]
                 if item 0 ?1 >= 95 and item 0 ?1 < 112 [set color-code 27]
                 if item 0 ?1 >= 112 [set color-code 17]
                 set color color-code
                 set cone-size item 2 ?1
    ]
         ]
    let draw-forc turtle-set drawers with [size = .05]
      set i 0
      set i 1
    while [i < length long-list] [
                        let head atan (item 0 item 1 item (i) long-list - item 0 item 1 item (i - 1) long-list)
                                      (item 1 item 1 item (i) long-list - item 1 item 1 item (i - 1) long-list)

                         set head (90 - head) mod 360

                        let points-list list (item 0 item 1 item i long-list - (((item 2 item i long-list) / scale) * (cos (head - 90)) ))
                                             (item 1 item 1 item i long-list - (((item 2 item i long-list) / scale) * (sin (head - 90)) ))

                        if item 0 points-list > min-pxcor and item 0 points-list < max-pxcor and
                           item 1 points-list > min-pycor and item 1 points-list < max-pycor [
                        create-drawers 1 [set size .02
                                          set color red
                                          setxy item 0 points-list item 1 points-list
                                          create-link-to one-of drawers with [xcor = item 0 item 1 item i long-list and ycor = item 1 item 1 item i long-list] [set color [color] of end2] ] ]


                        set points-list list (item 0 item 1 item i long-list - (((item 2 item i long-list) / scale) * (cos (head + 90)) ))
                                             (item 1 item 1 item i long-list - (((item 2 item i long-list) / scale) * (sin (head + 90)) ))

                        if item 0 points-list > min-pxcor and item 0 points-list < max-pxcor and
                           item 1 points-list > min-pycor and item 1 points-list < max-pycor [
                        create-drawers 1 [set size .03
                                          set color red
                                          setxy item 0 points-list item 1 points-list
                                          create-link-to one-of drawers with [xcor = item 0 item 1 item i long-list and ycor = item 1 item 1 item i long-list] [set color [color] of end2] ] ]

                           set i i + 1 ]

  report (list long-list)

end


;  Not sure I understand why this is done differently...

;JA: Is this function needed, Can't the EM determine how far the storm is from its location instead of the patch doing it?
to Coastal-Patches-Alerts
  ; INFO: Issue alerts for coastal patches based on the distance of the storm
  ; VARIABLES MODIFIED: alerts (evaculation order)
  ; PROCEDURES CALLED: None
  ; CALLED BY: Go

   ask ocean-patches with [alerts != 1 and county > 0] [  ;Ask only ocean patches that have not issued alerts yet
   ;ask patches with [alerts != 1 and county > 0 and not (elev >= 0 or elev <= 0)] [
   ;show " coastal alert"
   ;set pcolor green

   let working-forecast []   ;Creates a temporary variable for the current forecast
       if alerts != 1 [          ;Only runs this code if no evac orders issued already

       let fav one-of broadcasters with [not empty? broadcast]            ;Picks one Broadcaster
       if fav != nobody [set working-forecast [item 0 broadcast] of fav]  ;Imports the forecast from that Broadcaster ([[97.91666666666667 [-23.382636815154182 -71.83359999996831] 100.58333333333333 [9 1700]] [98.95833333333334 [-24.19109452660506 -68.58359999993581] 101.79166666666666 [9 1800]])

       if length working-forecast > 1 [
          set working-forecast sort-by [ [?1 ?2] -> distancexy item 0 item 1 ?1 item 1 item 1 ?1 < distancexy item 0 item 1 ?2 item 1 item 1 ?2 ] working-forecast ;forecast changes such that the closest distance of the hurricane center to the patch is listed first
             let set_right-left list item 0 working-forecast item 1 working-forecast ;"set_right-left" is equal to the latest two entries in the working foreacast
             set set_right-left sort-by [ [?1 ?2] -> item 0 item 3 ?1 + ((item 1 item 3 ?1 / 100) * (1 / 24)) > item 0 item 3 ?2 + ((item 1 item 3 ?2 / 100) * (1 / 24)) ] set_right-left ;Makes sure the first item in the list is temporally after the second item in the list
        ;JA: The time of landfall varies between each time step - why?
        set working-forecast first working-forecast ;"working-forecast" is now the latest time
              ;JA: storm-head does not seem needed
             let storm-head atan (item 0 item 1 item 1 set_right-left - item 0 item 1 item 0 set_right-left)
                                    (item 1 item 1 item 1 set_right-left - item 1 item 1 item 0 set_right-left)
             let direction atan (item 0 item 1 item 0 set_right-left - pxcor) (item 1 item 1 item 0 set_right-left - pycor)  ;pxcor and pycor are the patch coordinates. direction is the direction from the hurricane center to the patch. 0 degrees is straight up. 90 degrees is to the right.
           ;; determines how far out (temporally) till the storm reaches closest point
            let tc item 0 clock + ((item 1 clock / 100) * (1 / 24)) ;"tc" is the current time converted from day and hours
            let arriv item 0 item 3 working-forecast + ((item 1 item 3 working-forecast / 100) * (1 / 24)) ;"arriv" is the time the hurricane will make landfall
            ;JA: Won't we have problems if the month changes?
            let counter (arriv - tc) * 24 ;"counter" is the ours until arrival
          let interp_sz item 2 working-forecast ;size of the hurricane at landfall
          let intens item 0 working-forecast ;intensity of the hurricane at landfall
           let dist_trk distancexy item 0 item 1 working-forecast item 1 item 1 working-forecast ;Find the distance between the TC center and the patch point at landfall
           if (scale * dist_trk) < interp_sz [ set dist_trk 0 ] ;If the patch is within the 64-kt wind radii, set "dist_trk"=0

          if counter < earliest and dist_trk = 0 and intens >= wind-threshold[ set alerts 1 ] ;If the time before arrival is lower than "earliest", the patch is within the 64-kt wind radius, and the intensity is greater than the wind threshold, set alerts=1

      ] ] ]


end


to Issue-Alerts
  ; INFO: Used to determine if evacuation orders are needed.
  ; VARIABLES MODIFIED: orders
  ; PROCEDURES CALLED: None
  ; CALLED BY: Go (by Officials)

          if orders != 1 [          ;; only runs this code if no evac orders issued already

          if any? ocean-patches with [alerts = 1 and county = [[county] of patch-here] of myself] and not (land? = false) [

               let working-forecast [] ;Creates a temporary variable for the current forecast

               let fav one-of broadcasters with [not empty? broadcast]            ;Picks one Broadcaster
               if fav != nobody [set working-forecast [item 0 broadcast] of fav]  ;Imports the forecast from that Broadcaster


               if length working-forecast > 1 [
                  set working-forecast sort-by [ [?1 ?2] -> distancexy item 0 item 1 ?1 item 1 item 1 ?1 < distancexy item 0 item 1 ?2 item 1 item 1 ?2 ] working-forecast ;forecast changes such that the closest distance of the hurricane center to the patch is listed first
             set working-forecast first working-forecast ;"working-forecast" is now the latest time

           ;; determines how far out (temporally) till the storm reaches closest point
              let tc item 0 clock + ((item 1 clock / 100) * (1 / 24)) ;"tc" is the current time converted from day and hours
              let arriv item 0 item 3 working-forecast + ((item 1 item 3 working-forecast / 100) * (1 / 24)) ;"arriv" is the time the hurricane will make landfall
              let counter (arriv - tc) * 24 ;"counter" is the ours until arrival

            set when-issued counter ;"when-issued" is set to the number of hours before landfall that an evacuation order was issued
            set orders 1

               ] ] ]

          if orders = 1 [ set color white]

end



to Decision-Module
  ; INFO: The main Protective Action Decision-Making process called by citizen agents
  ; They check environmental cues, collect and process information, assess risk, assess
  ; alternative protective actions, and decide whether to act.
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY:


 ;; INFO COLLECTION PROCESSES

  ;;** SMB Why 3?
  ;; Personal interpretation of location in vulnerable zone
      let zone_warning 0
      if evac-zone = "A" [ set zone_warning 3 ]


  ;; Check for evacuation orders
      let nearby-official min-one-of officials [distance myself]
      let official-orders [orders] of nearby-official
      set when-evac-1st-ordered [when-issued] of nearby-official

  ;; ** SMB What is going on with direction here
  ;; ** SMB ASK about environmental cues ***
  ;; Check for environmental cues
        ;;let environmental-cues 0
        let direction 0
        if any? hurricanes  [set direction towards-nowrap one-of hurricanes ; reports the heading of the hurricane to an agent
                             if direction >= 0 and direction < 90 [ set direction item 8 item ticks hurricane-coords-best-track ]
                             if direction >= 90 and direction < 180 [ set direction item 9 item ticks hurricane-coords-best-track ]
                             if direction >= 180 and direction < 270 [ set direction item 6 item ticks hurricane-coords-best-track ]
                             if direction >= 270 and direction < 360 [ set direction item 7 item ticks hurricane-coords-best-track ]

         if (scale * distance one-of hurricanes) < direction [ set environmental-cues 1] ]


  ;; main pre-decisional processes
     ;; select a subset of broadcasters, aggregators, and social network
     ;; add their interpretation of the storm to agent's own list
       set forecast-options []
       set interpreted-forecast []

       set forecast-options (sentence
                   (list memory)
                   map [ ?1 -> list item 1 ?1 [broadcast] of item 0 ?1 ] broadcaster-list
                   map [ ?1 -> list item 1 ?1 [info] of item 0 ?1 ] aggregator-list
                   map [ ?1 -> list item 1 ?1 [interpreted-forecast] of item 0 ?1 ] my-network-list
                   )

; these lists can be around 5 long and the network list tends to be the smallest at 2-3 and a total of 15 sources then memory too!


     ;; attention to info?
     ;; ignore some previously collected info
  ;*** SMB ????
        repeat random (length forecast-options - 1) [
        set forecast-options but-first shuffle forecast-options ]

    ;; sets agent's own interpretation of the storm track (use broadcasters and social network).
    ;; picks one from their own assessment of the most reliable source

    set forecast-options sort-by [ [?1 ?2] -> item 0 ?1 > item 0 ?2 ] forecast-options
    set forecast-options filter [ ?1 -> item 1 ?1 != [] ] forecast-options

;    let surge-info map [list item 0 ? item 1 item 1 ?] options
    set forecast-options map [ ?1 -> list item 0 ?1 item 0 item 1 ?1 ] forecast-options


    if not empty? forecast-options and not empty? item 1 item 0 forecast-options [    ;; rest of following code dependent on this conditional

     let int1 map [ ?1 -> item 1 ?1 ] forecast-options

     ;; new filter to keep the list of options constrained to the forecasts visible on the map
     set int1 map [ ?1 -> filter [ ??1 -> item 0 item 1 ??1 > min-pxcor and item 0 item 1 ??1 < max-pxcor and item 1 item 1 ??1 > min-pycor and item 1 item 1 ??1 < max-pycor ] ?1 ] int1


   ;; short list of days included in the agent's forecast
    let day-list sort remove-duplicates map [ ?1 -> item 0 ?1 ] map remove-duplicates reduce sentence map [ ?1 -> map [ ??1 -> item 3 ??1 ] ?1 ] int1

   ;; makes a list of all possible days/hours included in the forecast grab bag
    let s-list []
    foreach day-list [ ?1 ->
     let t ?1
     set s-list sentence filter [ ??1 -> item 0 ??1 = t ] map remove-duplicates reduce sentence map [ ??1 -> map [ ???1 -> item 3 ???1 ] ??1 ] int1 s-list
     set s-list sort-by [ [??1 ??2] -> (item 0 ??1 * 2400 + item 1 ??1) < (item 0 ??2 * 2400 + item 1 ??2) ] remove-duplicates s-list
     ]


   ;; sets up lists for blending forecasts, weighting according to trust factor
   ;; functionally, for each day/hour all the right forecasts are grouped and weighted
   ;; the output variable (interp) is a mashup forecast
    let c-matrix []
    let d-matrix []
    let x-matrix []
    let y-matrix []

    foreach s-list [ ?1 ->
      let t ?1
      let c []
      let d []
      let x []
      let y []
        (foreach int1 forecast-options [ [??1 ??2] ->
          let TF item 0 ??2
          foreach ??1 [ ???1 ->
          if item 3 ???1 = t [ set c lput list TF item 0 ???1 c
                            set d lput list TF item 2 ???1 d
                            set x lput list TF item 0 item 1 ???1 x
                            set y lput list TF item 1 item 1 ???1 y
         ] ] ])
        set c-matrix lput sum map [ ??1 -> (item 0 ??1 * (item 1 ??1 / (sum map [ ???1 -> item 0 ???1 ] c))) ] c c-matrix
        set d-matrix lput sum map [ ??1 -> (item 0 ??1 * (item 1 ??1 / (sum map [ ???1 -> item 0 ???1 ] d))) ] d d-matrix
        set x-matrix lput sum map [ ??1 -> (item 0 ??1 * (item 1 ??1 / (sum map [ ???1 -> item 0 ???1 ] x))) ] x x-matrix
        set y-matrix lput sum map [ ??1 -> (item 0 ??1 * (item 1 ??1 / (sum map [ ???1 -> item 0 ???1 ] y))) ] y y-matrix
        ]

     set interpreted-forecast (map [ [?1 ?2 ?3 ?4 ?5] -> (list ?2 list ?4 ?5 ?3 ?1) ] s-list c-matrix d-matrix x-matrix y-matrix)


    ;; identifies the forecast info for the closest point (spatially) the forecasted storm will come to the agent

     let X_V first sort-by [ [?1 ?2] -> distancexy item 0 item 1 ?1 item 1 item 1 ?1 < distancexy item 0 item 1 ?2 item 1 item 1 ?2 ] interpreted-forecast

    set interpreted-forecast list interpreted-forecast ["no surge forecast"]

    ;; sets memory variable for use in subsequent loops, and links that to the agent's self trust parameter
     set memory list self-trust interpreted-forecast
     if color = blue [set color white]

    ;; determines how far out (temporally) till the storm reaches closest point
     let tc item 0 clock + ((item 1 clock / 100) * (1 / 24))
     let arriv item 0 item 3 X_V + ((item 1 item 3 X_V / 100) * (1 / 24))
     let counter (arriv - tc) * 24

    ;; define variables that set the "utility curve" used to assess risk (and related decisions)
     let X_VALUE counter                     ; x value of the risk function is  time till arrival
     let CENTER random-normal 36 3          ; sets peak utility/risk at 48 before arrival... (random number w/ mean 46 and stdev 2)
     let SD_SPREAD random-normal 24 12        ; sets the incline/decline rate of the risk function... (random number w/ mean 10 stdev 2)
     let HEIGHT 0                            ; recalculated below to set the height fo the risk function


   ;; HEIGHT is calculated as a mix of storm intensity, distance from track, recommendations (evac zone)... weighted/calibrated to get reasonable behavior
   ;; given the Gaussian curve below, HEIGHT values look like this (.04 gives a peak at just about 10, 0.2 gives 20, 0.08 gives 5... you see the relationship)
   ;; note that most agents' risk-life threshold is somewhere near 10

   ;; dertimines how far out (spatially) for the storm's closest approach
     let dist_trk distancexy item 0 item 1 X_V item 1 item 1 X_V

   ;; parses the size of the error of the storm forecast
     let err_bars item 2 X_V

   ;; parses the intensity of the storm forecast
     let intensity item 0 X_V

   ;; conditional sets whether the intensity of the storm is worth considering in the risk function
     ifelse intensity >= 95 [set intensity 0] [set intensity 1]

   ;; conditional sets whether the agent's zone (set above in pre-decisional processes) should be considered in the risk function
     let zone 1
     ifelse zone_warning = 3 [set zone 0] [set zone 1]

   ;; conditional sets whether the agent is inside or outside of the storm track
     if (scale * dist_trk) < err_bars [ set dist_trk 0 ]

   ;; transforms the distance from the storm track into a value used in the risk function
     set dist_trk   (((scale * .5 * dist_trk) * (.0011 / err_bars)) + .0011)

   ;; sets the HEIGHT variable as a function of distance from the storm track + zone + intensity (weighted/calibrated to get reasonable numbers)
     set HEIGHT sqrt (dist_trk + (.003 * zone) + (.000525 * intensity))


   ;; finally, calculates risk (Gaussian curve based on the variables calculated above)
    let risk ((1 / (HEIGHT * sqrt (2 * pi) )) * (e ^ (-1 * (((X_VALUE - CENTER) ^ 2) / (2 * (SD_SPREAD ^ 2))))))  ;; bell curve


    if self = watching [ set risk-funct risk]

   ;; takes the risk assessment and adds a little error either side
    let final-risk random-normal risk .5

    if self = watching [ set risk-error (final-risk - risk) ]

    set final-risk 1.1 * final-risk

    let temp-f-risk final-risk

   ;; adds in evacuation orders
     ;; checks if they even think they're in a relevant evac zone, changes value for this math...
    ifelse zone = 0  [set zone 1] [set zone 0.4] ;[set zone 1] [set zone 0.4]
    set final-risk final-risk + (trust-authority * 6 * official-orders * zone)   ;; trust in authority?  ;;; default is 9, trying 6 and 1.5x for forecasts.


    if self = watching [ set risk-orders (trust-authority * 6 * official-orders * zone) ]

   ;; adds in environmental cues
    set final-risk final-risk + (3 * environmental-cues)


    if self = watching [ set risk-env (3 * environmental-cues) ]

    set risk-packet (list precision final-risk 3 precision (3 * environmental-cues) 3 precision (trust-authority * 6 * official-orders * zone) 3)

    set risk-estimate lput final-risk risk-estimate

     let c1 (temp-f-risk) * forc-w
     let c2 ((trust-authority * 6 * official-orders * zone)) * evac-w
     let c3 ((3 * environmental-cues)) * envc-w

     set final-risk sum (list c1 c2 c3)

    if kids-under-18? = true [set final-risk final-risk + (final-risk * under-18-assessment-increase)]
    if adults-over-65? = true [set final-risk final-risk - (final-risk * over-65-assessment-decrease)]
    if limited-english? = true [set final-risk final-risk - (final-risk * limited-english-assessment-decrease)]
    if food-stamps? = true [set final-risk final-risk - (final-risk * foodstamps-assessment-decrease)]
    if no-vehicle? = true [set final-risk final-risk - (final-risk * no-vehicle-assessment-modification)]
    if no-internet? = true [set final-risk final-risk - (final-risk * no-internet-assessment-modification)]

    set risk-watcher final-risk


   ;; conditionals determine the decision outcome based on the risk assessment (records what they did and when they did it, updates colors)
   ;; note "feedback1" variable sets the frequency an agent runs this whole loop, min is 1 tick (every step), max is 12 ticks
    if final-risk > risk-life [set color orange
                         set completed fput (list "evacuate" clock counter) completed
                         ]
    if final-risk < risk-life and final-risk > risk-property [set color green
                         set decision-module-frequency round (decision-module-frequency / 2)
                         if decision-module-frequency = 0 [set decision-module-frequency 1]
                         set completed fput (list "other_PA" clock counter) completed ]
    if final-risk < risk-property and final-risk > info-up [ set decision-module-frequency round (decision-module-frequency / 2)
                                            if decision-module-frequency = 0 [set decision-module-frequency 1]
                                            ]
    if final-risk < info-up and final-risk > info-down [
      ]
    if final-risk < info-down  [set decision-module-frequency round (decision-module-frequency * 2)
                       if decision-module-frequency > 32 [set decision-module-frequency 32]
                       ]

     if self = watching [
      set risk-total final-risk ]

  ]

end


to Just-Collect-Info
  ; INFO: This is the main pre-decisional processes. The agent selects a subset of broadcasters, officials, aggregators, and social network
  ; They then add their interpretation of the storm to agent's own list
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY:


       set forecast-options []
       set interpreted-forecast []

       set forecast-options (sentence
                   (list memory)
                   map [ ?1 -> list item 1 ?1 [broadcast] of item 0 ?1 ] broadcaster-list
                   map [ ?1 -> list item 1 ?1 [info] of item 0 ?1 ] aggregator-list
                   map [ ?1 -> list item 1 ?1 [interpreted-forecast] of item 0 ?1 ] my-network-list
                   )

     ;; attention to info?
     ;; ignore some previously collected info
        repeat random (length forecast-options - 1) [
        set forecast-options but-first shuffle forecast-options ]

    ;; sets agent's own interpretation of the storm track (use broadcasters and social network).
    ;; picks one from their own assessment of the most reliable source

    set forecast-options sort-by [ [?1 ?2] -> item 0 ?1 > item 0 ?2 ] forecast-options
    set forecast-options filter [ ?1 -> item 1 ?1 != [] ] forecast-options
    set interpreted-forecast first forecast-options

end

to-report Save-Individual-Cit-Ag-Evac-Records
  ; INFO: Used at the conclusion of the simulation. Records simulation information for each agent which creates a large data file.
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY: Behavior Space

  let filename evac-filename
  file-open word filename ".csv"
  let text-out (sentence ",agent,xcor,ycor,kids.under.18,adults.over.65,limited.english,foodstamps,no.vehicle,no.internet,census.tract.number,evac.zone,completed.actions,when.evac.1st.ordered,bs.run.number,which.storm,distribute.population,earliest,wind.threshold,forc.w,evac.w,envc.w,network.distance,network.size,tract.information,")
  file-type text-out
  file-print ""

  ask citizen-agents[
  set text-out (sentence ","who","xcor","ycor","kids-under-18?","adults-over-65?","limited-english?","food-stamps?","no-vehicle?","no-internet?","census-tract-number","evac-zone","completed","when-evac-1st-ordered","behaviorspace-run-number","which-storm?","distribute_population","earliest","wind-threshold","forc-w","evac-w","envc-w","network-distance","network-size","tract-information",")
  file-type text-out
  file-print ""
  ]

  file-close

  report "bogus"

end


to-report Save-Global-Evac-Statistics
  ; INFO: Saves evacuation information for the whole simulation - aggregate for all of the agents.
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY: Behavior Space


 ifelse ticks > 115 [

 let rec-matrix []

 foreach sort citizen-agents [ ?1 ->
   ask ?1 [
   let temp-list []
   set temp-list lput ifelse-value (not empty? completed and item 0 item 0 completed = "evacuate") [1] [0] temp-list
     ; starts with evacuated or not
   set temp-list lput ifelse-value ([distance-nowrap myself] of min-one-of patches with [not (elev >= 0 or elev <= 0)] [distance-nowrap myself] <= 1.5) [1] [0] temp-list


  ; filter to only shown hurricane coordinates
   let w-l filter [?x -> item 0 ?x > min-pxcor and item 0 ?x < max-pxcor and
                           item 1 ?x > min-pycor and item 1 ?x < max-pycor] hurricane-coords-best-track
   set w-l map [?x -> (list item 0 ?x item 1 ?x item 2 ?x item 3 ?x item 4 ?x
          ifelse-value (towardsxy item 0 ?x item 1 ?x <= 360) [item 6 ?x] [
          ifelse-value (towardsxy item 0 ?x item 1 ?x <= 270) [item 5 ?x] [
          ifelse-value (towardsxy item 0 ?x item 1 ?x <= 180) [item 8 ?x] [item 7 ?x] ]]
          ifelse-value (towardsxy item 0 ?x item 1 ?x <= 360) [item 10 ?x] [
          ifelse-value (towardsxy item 0 ?x item 1 ?x <= 270) [item 9 ?x] [
          ifelse-value (towardsxy item 0 ?x item 1 ?x <= 180) [item 12 ?x] [item 11 ?x] ]]
       )] w-l

   set w-l map [?x ->
     (list ifelse-value (scale * distancexy item 0 ?x item 1 ?x > item 5 ?x) [0] [1]
           ifelse-value (scale * distancexy item 0 ?x item 1 ?x > item 6 ?x) [0] [1]
       )] w-l

   let s-l []
   if member? [1 0] w-l [set s-l lput 1 s-l]
   if member? [1 1] w-l [set s-l lput 1 s-l]
   if s-l = [1] [set s-l [1 0]]
   if s-l = [] [set s-l [0 0]]
   set temp-list sentence temp-list s-l
   set temp-list lput ifelse-value (not empty? completed and item 0 item 0 completed = "evacuate") [round item 2 item 0 completed] [-9] temp-list

;; just lights up agents that evacuated in the zones
   if but-last temp-list = [1 1 1 1] [set color [230 159 0]]
   if but-last temp-list = [0 1 1 1] [set color gray]
   if but-last temp-list = [1 1 1 0] [set color [0 158 115]]
   if but-last temp-list = [0 1 1 0] [set color gray]
   if but-last temp-list = [1 1 0 0] [set color [0 114 178]]
   if but-last temp-list = [0 1 0 0] [set color gray]
   if but-last temp-list = [1 0 1 1] [set color [240 228 66]]
   if but-last temp-list = [0 0 1 1] [set color gray]
   if but-last temp-list = [1 0 1 0] [set color [86 180 233]]
   if but-last temp-list = [0 0 1 0] [set color gray]
   if but-last temp-list = [1 0 0 0] [set color white]
   if but-last temp-list = [0 0 0 0] [set color gray]

   set rec-matrix lput temp-list rec-matrix
    ] ]

  let coastal/64 length filter [?x -> but-last ?x = [1 1 1 1] ] rec-matrix
  let coastal/34 length filter [?x -> but-last ?x = [1 1 1 0] ] rec-matrix
  let coastal/out length filter [?x -> but-last ?x = [1 1 0 0] ] rec-matrix
  let inland/64 length filter [?x -> but-last ?x = [1 0 1 1] ] rec-matrix
  let inland/34 length filter [?x -> but-last ?x = [1 0 1 0] ] rec-matrix
  let inland/out length filter [?x -> but-last ?x = [1 0 0 0] ] rec-matrix

  let per-coastal/64 precision (length filter [x? -> but-last x? = [1 1 1 1] ] rec-matrix / ifelse-value ((length filter [x? -> but-last x? = [1 1 1 1] ] rec-matrix + length filter [x? -> but-last x? = [0 1 1 1] ] rec-matrix) != 0) [(length filter [x? -> but-last x? = [1 1 1 1] ] rec-matrix + length filter [x? -> but-last x? = [0 1 1 1] ] rec-matrix)] [.00000001]) 2
  let per-coastal/34 precision (length filter [x? -> but-last x? = [1 1 1 0] ] rec-matrix / ifelse-value ((length filter [x? -> but-last x? = [1 1 1 0] ] rec-matrix + length filter [x? -> but-last x? = [0 1 1 0] ] rec-matrix) != 0) [(length filter [x? -> but-last x? = [1 1 1 0] ] rec-matrix + length filter [x? -> but-last x? = [0 1 1 0] ] rec-matrix)] [.00000001]) 2
  let per-coastal/out precision (length filter [x? -> but-last x? = [1 1 0 0] ] rec-matrix / ifelse-value ((length filter [x? -> but-last x? = [1 1 0 0] ] rec-matrix + length filter [x? -> but-last x? = [0 1 0 0] ] rec-matrix) != 0) [(length filter [x? -> but-last x? = [1 1 0 0] ] rec-matrix + length filter [x? -> but-last x? = [0 1 0 0] ] rec-matrix)] [.00000001]) 2
  let per-inland/64 precision (length filter [x? -> but-last x? = [1 0 1 1] ] rec-matrix / ifelse-value ((length filter [x? -> but-last x? = [1 0 1 1] ] rec-matrix + length filter [x? -> but-last x? = [0 0 1 1] ] rec-matrix) != 0) [(length filter [x? -> but-last x? = [1 0 1 1] ] rec-matrix + length filter [x? -> but-last x? = [0 0 1 1] ] rec-matrix)] [.00000001]) 2
  let per-inland/34 precision (length filter [x? -> but-last x? = [1 0 1 0] ] rec-matrix / ifelse-value ((length filter [x? -> but-last x? = [1 0 1 0] ] rec-matrix + length filter [x? -> but-last x? = [0 0 1 0] ] rec-matrix) != 0) [(length filter [x? -> but-last x? = [1 0 1 0] ] rec-matrix + length filter [x? -> but-last x? = [0 0 1 0] ] rec-matrix)] [.00000001]) 2
  let per-inland/out precision (length filter [x? -> but-last x? = [1 0 0 0] ] rec-matrix / ifelse-value ((length filter [x? -> but-last x? = [1 0 0 0] ] rec-matrix + length filter [x? -> but-last x? = [0 0 0 0] ] rec-matrix) != 0) [(length filter [x? -> but-last x? = [1 0 0 0] ] rec-matrix + length filter [x? -> but-last x? = [0 0 0 0] ] rec-matrix)] [.00000001]) 2

  let tot-coastal/64 (length filter [x? -> but-last x? = [1 1 1 1] ] rec-matrix + length filter [x? -> but-last x? = [0 1 1 1] ] rec-matrix)
  let tot-coastal/34 (length filter [x? -> but-last x? = [1 1 1 0] ] rec-matrix + length filter [x? -> but-last x? = [0 1 1 0] ] rec-matrix)
  let tot-coastal/out (length filter [x? -> but-last x? = [1 1 0 0] ] rec-matrix + length filter [x? -> but-last x? = [0 1 0 0] ] rec-matrix)
  let tot-inland/64 (length filter [x? -> but-last x? = [1 0 1 1] ] rec-matrix + length filter [x? -> but-last x? = [0 0 1 1] ] rec-matrix)
  let tot-inland/34 (length filter [x? -> but-last x? = [1 0 1 0] ] rec-matrix + length filter [x? -> but-last x? = [0 0 1 0] ] rec-matrix)
  let tot-inland/out (length filter [x? -> but-last x? = [1 0 0 0] ] rec-matrix + length filter [x? -> but-last x? = [0 0 0 0] ] rec-matrix)

  let output-list (list per-coastal/64 per-coastal/34 per-coastal/out per-inland/64 per-inland/34 per-inland/out coastal/64 coastal/34 coastal/out inland/64 inland/34 inland/out
               tot-coastal/64 tot-coastal/34 tot-coastal/out tot-inland/64 tot-inland/34 tot-inland/out)

  let output-list-a (list per-coastal/64 per-coastal/34 per-coastal/out per-inland/64 per-inland/34 per-inland/out coastal/64 coastal/34 coastal/out inland/64 inland/34 inland/out
               tot-coastal/64 tot-coastal/34 tot-coastal/out tot-inland/64 tot-inland/34 tot-inland/out)

  let allpct sum (list coastal/64 coastal/34 coastal/out inland/64 inland/34 inland/out) /
             sum (list tot-coastal/64 tot-coastal/34 tot-coastal/out tot-inland/64 tot-inland/34 tot-inland/out)

  let time-coastal/64 map [x? -> last x?] filter [x? -> but-last x? = [1 1 1 1] ] rec-matrix
  let time-coastal/34 map [x? -> last x?]  filter [x? -> but-last x? = [1 1 1 0] ] rec-matrix
  let time-coastal/out map [x? -> last x?] filter [x? -> but-last x? = [1 1 0 0] ] rec-matrix
  let time-inland/64 map [x? -> last x?] filter [x? -> but-last x? = [1 0 1 1] ] rec-matrix
  let time-inland/34 map [x? -> last x?] filter [x? -> but-last x? = [1 0 1 0] ] rec-matrix
  let time-inland/out map [x? -> last x?] filter [x? -> but-last x? = [1 0 0 0] ] rec-matrix
  let time-officials/all [round when-issued] of officials with [when-issued != 0]

  let total-per-zone (list (item 6 output-list-a + item 12 output-list-a)
                           (item 7 output-list-a + item 13 output-list-a)
                           (item 8 output-list-a + item 14 output-list-a)
                           (item 9 output-list-a + item 15 output-list-a)
                           (item 10 output-list-a + item 16 output-list-a)
                           (item 11 output-list-a + item 17 output-list-a)
                           count officials with [when-issued != 0])
;  show total-per-zone
   let evacs-timing-list (list time-coastal/64 time-coastal/34 time-coastal/out time-inland/64 time-inland/34 time-inland/out time-officials/all)
   let hist-list []
   let hist-pcts []

;; shows histogram counts for 90 hours out till 18 hours past landfall

    (foreach evacs-timing-list total-per-zone [ [?1 ?2] ->
     let current-list ?1
     let t-p-z ?2
      (foreach [84 78 72 66 60 54 48 42 36 30 24 18 12 6 0 -6 -12 -18] [90 84 78 72 66 60 54 48 42 36 30 24 18 12 6 0 -6 -12] [ [x?1 x?2] ->
          let i x?1
          let j x?2
        ;  show (list t-p-z length current-list length filter [? >= i and ? < j] current-list)
          set hist-list lput length filter [x? -> x? >= i and x? < j] current-list hist-list
          ifelse (t-p-z > 0) [set hist-pcts lput  ((length filter [x? -> x? >= i and x? < j] current-list) / t-p-z) hist-pcts] [set hist-pcts lput 0 hist-pcts]
         ])
         set hist-list lput "--" hist-list
         set hist-pcts lput "--" hist-pcts
        ])


   let op (sentence "" behaviorspace-run-number which-storm? distribute_population earliest wind-threshold forc-w evac-w envc-w allpct network-distance network-size test-factor-proportion under-18-assessment-increase "|" output-list-a "|" hist-list "|" hist-pcts "|")

  file-open word output-filename ".txt"
    file-type op
    file-print ""
  file-close


  report output-list ] [ report "N/A"]

end

to Show-Links
  ; INFO: Link the nodes in the model. Makes a good picture, but functionally does nothing
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY:

  ask citizen-agents [
     foreach my-network-list [ ?1 ->
       if item 0 ?1 != nobody [
     create-link-to item 0 ?1 [set color yellow] ] ] ]


end




to Load-GIS-HPC
  ; INFO: Load GIS information. It is a HPC Specific version so that the paths don't need to be changed and two versions of the model don't need to be maintained.
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY:

  __clear-all-and-reset-ticks

    if which-storm? = "WILMA" or which-storm? = "WILMA_IDEAL" or which-storm? = "CHARLEY_REAL" or which-storm? = "CHARLEY_IDEAL" or which-storm? = "CHARLEY_BAD" or which-storm? = "IRMA" [set which-region? "FLORIDA"]
    if which-storm? = "HARVEY"  [set which-region? "GULF"]
    if which-storm? = "MICHAEL"  [set which-region? "UNKNOWN"]


     let elevation 0
     let density-map 0
     let counties 0

     if which-REGION? = "FLORIDA" [
      gis:load-coordinate-system "/home/sbergin/CHIME/REGION/FLORIDA/GIS/block_density.prj"                  ; NetLogo needs a prj file to set up the conversion from GIS to netlogo grid
      set elevation gis:load-dataset "/home/sbergin/CHIME/REGION/FLORIDA/GIS/Florida_SRTM_1215.asc"         ; Raster map - SRTM elevation data (downscaled using GRASS GIS)
      set density-map gis:load-dataset "/home/sbergin/CHIME/REGION/FLORIDA/GIS/Pop_Density_1215.asc"            ; Raster map - Population density (calculated by census tract, modified for use w/ GRASS)
      set county-seat-list []
      set county-seats gis:load-dataset "/home/sbergin/CHIME/REGION/FLORIDA/GIS/county_seats.shp"           ; Vector map (points) - location of county seats
      set counties gis:load-dataset "/home/sbergin/CHIME/REGION/FLORIDA/GIS/counties_1.asc"                 ; Raster map - counties
       foreach but-last gis:feature-list-of county-seats [ ?1 ->
        set county-seat-list lput list gis:property-value ?1 "CAT" (gis:location-of (first (first (gis:vertex-lists-of ?1)))) county-seat-list
       ]]
     if which-REGION? = "GULF" [
      gis:load-coordinate-system "REGION/GULF/GIS/block_density.prj"                  ; NetLogo needs a prj file to set up the conversion from GIS to netlogo grid
      set elevation gis:load-dataset "REGION/GULF/GIS/gulf_states_extended.asc"         ; Raster map - SRTM elevation data (downscaled using GRASS GIS)
      set density-map gis:load-dataset "REGION/GULF/GIS/gulf_states_pop_density_extended.asc"            ; Raster map - Population density (calculated by census tract, modified for use w/ GRASS)
      set county-seat-list []
      set county-seats gis:load-dataset "REGION/GULF/GIS/gulf_states_county_seats.shp"           ; Vector map (points) - location of county seats
      set counties gis:load-dataset "REGION/GULF/GIS/gulf_states_counties_extended.asc"                 ; Raster map - counties
       foreach but-last gis:feature-list-of county-seats [ ?1 ->
        set county-seat-list lput list gis:property-value ?1 "CAT" (gis:location-of (first (first (gis:vertex-lists-of ?1)))) county-seat-list
       ]
  ]

     gis:set-world-envelope-ds gis:envelope-of elevation

     let world gis:world-envelope
     let degree-x abs (item 1 world - item 0 world) / (2 * max-pxcor)   ;; sets grid cell size in degrees
     let degree-y abs (item 3 world - item 2 world) / (2 * max-pycor)

     set grid-cell-size list degree-x degree-y  ;; holds x and y grid cell size in degrees
     set re0-0 list (((item 0 world - item 1 world) / 2) + item 1 world) (((item 2 world - item 3 world) / 2) + item 3 world)
     ;;show re0-0  ;; identifies the 0,0 center of the map (degrees)

       gis:apply-raster elevation elev
       gis:apply-raster density-map density
       gis:apply-raster counties county
       gis:paint elevation 0 ;; the painted raster does not necessarily correspond to the elevation
       ask patches [set land? true]
       ;ask patches with [not (dens >= 0 or dens <= 0)] [set pcolor 102 set land? false]
       ask patches with [not (elev >= 0 or elev <= 0)] [set pcolor 102 set land? false]

       set land-patches patches with [land? = true]
       set ocean-patches patches with [land? = false]
     file-close-all
     set using-hpc? true

  print "using HPC"
  ;random-seed 99
end

to Load-Hurricane-HPC
  ; INFO: Load Hurricane information. It is a HPC Specific version so that the paths don't need to be changed and two versions of the model don't need to be maintained.
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY:

  let storm-file ""
    if which-storm? = "HARVEY" [ set storm-file "/home/sbergin/CHIME/STORMS/HARVEY/HARVEY.txt" ]
    if which-storm? = "WILMA" [ set storm-file "/home/sbergin/CHIME/STORMS/WILMA/WILMA_NEW.csv" ]          ;; defines storm file based on pull-down menu on the interface
    if which-storm? = "WILMA_IDEAL" [set storm-file "/home/sbergin/CHIME/STORMS/WILMA_IDEAL/WILMA_NEW.csv" ]
    if which-storm? = "CHARLEY_REAL" [ set storm-file "/home/sbergin/CHIME/STORMS/CHARLEY_REAL/CHARLEY.txt" ]
    if which-storm? = "CHARLEY_IDEAL" [ set storm-file "/home/sbergin/CHIME/STORMS/CHARLEY_IDEAL/CHARLEY.txt" ]
    if which-storm? = "CHARLEY_BAD" [ set storm-file "/home/sbergin/CHIME/STORMS/CHARLEY_BAD/CHARLEY.txt" ]
    if which-storm? = "IRMA" [ set storm-file "/home/sbergin/CHIME/STORMS/IRMA/IRMA.txt" ]

  file-open storm-file  ; imports csv of storm track, intensity, etc

  ;; this code block parses the csv and places the storm info in the hurricane-file array
  let hurricane-file []
  while [ not file-at-end? ]
    [ set hurricane-file sentence hurricane-file file-read-line ]
  file-close

  let Tparsed ""
  let parsed []
  let all_parsed []
  foreach hurricane-file [ ?1 ->
     let i 0
   while [i < length ?1] [
     set Tparsed word Tparsed item i ?1
     if item i ?1 = "," [ set parsed lput remove "," Tparsed parsed
                         set Tparsed ""
                         ]
              set i i + 1 ]
     set all_parsed lput parsed all_parsed
     set parsed [] ]

  set all_parsed but-first all_parsed
  set best-track-data map [ ?1 -> (list item 3 ?1 but-last item 4 ?1 replace-item 1 but-last item 5 ?1
      "-" item 6 ?1 item 7 ?1 item 0 ?1  item 1 ?1 item 8 ?1 item 9 ?1 item 10 ?1 item 11 ?1 item 16 ?1
      item 17 ?1 item 18 ?1 item 19 ?1) ] all_parsed  ;; type; xcor, ycor, windspeed; pressure; day ; winds 34 kt quads; winds 64 kt quads
end

to Load-Forecasts-HPC
  ; INFO: Load Forecast information. It is a HPC Specific version so that the paths don't need to be changed and two versions of the model don't need to be maintained.
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY:

  set forecast-matrix []

   let storm-file ""
    if which-storm? = "HARVEY" [ set storm-file "/home/sbergin/CHIME/STORMS/HARVEY/HARVEY ADVISORIES.txt" ]
    if which-storm? = "WILMA" [ set storm-file "/home/sbergin/CHIME/STORMS/WILMA/WILMA ADVISORIES.txt" ]              ;; defines the correct list of advisories from pull-down menu
    if which-storm? = "WILMA_IDEAL" [set storm-file "/home/sbergin/CHIME/STORMS/WILMA_IDEAL/FAKE_WILMA ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_REAL" [ set storm-file "/home/sbergin/CHIME/STORMS/CHARLEY_REAL/CHARLEY ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_IDEAL" [ set storm-file "/home/sbergin/CHIME/STORMS/CHARLEY_IDEAL/FAKE_CHARLEY ADVISORIES.txt" ]
    if which-storm? = "CHARLEY_BAD" [set storm-file "/home/sbergin/CHIME/STORMS/CHARLEY_BAD/BAD_FAKE_CHARLEY ADVISORIES.txt" ]
    if which-storm? = "IRMA" [set storm-file "/home/sbergin/CHIME/STORMS/IRMA/IRMA ADVISORIES.txt" ]

 let file-list []

 ;; the storm-file is a list of all the advisories, which are stored as separate text files directly from NOAA/NHC website
 ;; this index file is parsed and then each of the advisories is parsed for relevant forecast information

 file-open storm-file
  while [not file-at-end?] [ set file-list lput file-read-line file-list]
 file-close

 foreach file-list [ ?1 ->
 file-open ?1
  let forecast-file []
  while [ not file-at-end? ]
    [
      set forecast-file sentence forecast-file word file-read-line " "
    ]
  file-close

  let Tparsed ""
  let parsed []
  let all_parsed []

;; The advisory parser is fairly complicated... because the advisories themselves are much more than a simple rectangular data file...

  foreach forecast-file [ ??1 ->
     let i 0
   while [i < length ??1 ] [
     set Tparsed word Tparsed item i ??1
     if item i ??1 = " " [ set parsed lput remove " " Tparsed parsed
                         set Tparsed ""
                         ]
              set i i + 1
      ]
     set all_parsed lput parsed all_parsed
     set parsed []
    ]

  let s-line remove "" item 4 all_parsed
  let schedule list read-from-string item 3 s-line read-from-string but-last item 0 s-line
  let forecasts filter [ ??1 -> length ??1 > 2 and item 1 ??1 = "VALID" ]  all_parsed
  set forecasts map [ ??1 -> remove "" ??1 ] forecasts

  while [length item 2 last forecasts > 10 and substring item 2 last forecasts (length item 2 last forecasts - 5)  (length item 2 last forecasts - 0)  = "ORBED"] [set forecasts but-last forecasts]

  let winds but-first filter [ ??1 -> length ??1 > 2 and item 0 ??1 = "MAX" ]  all_parsed
  while [length winds < length forecasts] [ set winds (sentence winds "")]


  set winds map [ ??1 -> remove "" ??1 ] winds

  let dia64 map [ ??1 -> remove "" ??1 ] filter [ ??1 -> item 0 ??1 = "64" ] all_parsed
  let dia34 map [ ??1 -> remove "" ??1 ] filter [ ??1 -> item 0 ??1 = "34" ] all_parsed

 let dia34-list []
 if not empty? dia34 [
 set dia34-list map [ ??1 -> map [ ???1 -> read-from-string ???1 ] but-first map [ ???1 -> but-last but-last ???1 ] remove "" map [ ???1 -> remove "KT" remove "." ???1 ]  ??1 ] dia34
 set dia34-list but-first dia34-list ]
 while [length dia34-list < length forecasts] [
 set dia34-list (sentence dia34-list "") ]

 let dia64-list []
 if not empty? dia64 [
 set dia64-list map [ ??1 -> map [ ???1 -> read-from-string ???1 ] but-first map [ ???1 -> but-last but-last ???1 ] remove "" map [ ???1 -> remove "KT" remove "." ???1 ]  ??1 ] dia64
 set dia64-list but-first dia64-list ]
 while [length dia64-list < length forecasts] [
 set dia64-list (sentence dia64-list "") ]

  set forecast-matrix lput fput schedule (map [ [??1 ??2 ??3 ??4] -> (sentence
                   read-from-string substring item 2 ??1  0 position "/" item 2 ??1
                   read-from-string substring item 2 ??1 (position "/" item 2 ??1 + 1) position "Z" item 2 ??1
                  (( read-from-string substring item 3 ??1 0 4 - item 1 re0-0) / item 1 grid-cell-size)  ; lat
                  (((-1 * read-from-string substring item 4 ??1 0 4) - item 0 re0-0) / item 0 grid-cell-size)  ; lon
                   read-from-string item 2 ??2 ; wind max
                   (list ??3) (list ??4) ) ; wind dia34 (NE SE SW NW) and dia64 (NE SE SW NW)
      ]
                forecasts winds dia34-list dia64-list) forecast-matrix
  ]

 ;;show forecast-matrix

 file-close-all
end

to Setup-HPC
  ; INFO:
  ; VARIABLES MODIFIED:
  ; PROCEDURES CALLED
  ; CALLED BY:



  __clear-all-and-reset-ticks

  set using-hpc? true

  ;;Load Geographic Data Used in the Simulation
  Load-GIS-HPC


  Load-Hurricane-HPC

  ;; *SMB FOR HPC the load forecast procedure needs to be updated
  ifelse which-storm? = "IRMA" or  which-storm? = "MICHAEL" [ Load-Forecasts-New ] [Load-Forecasts-HPC]


  set scale (item 0 grid-cell-size * 60.0405)  ;; THIS SHOULD BE the size of a grid cell in nautical miles, more or less ;; 60.0405 nm per degree

  Generate-Storm  ;; generates the hurricane

  set clock list item 3 item ticks hurricane-coords-best-track  item 4 item ticks hurricane-coords-best-track    ;; defines the clock

  ;; Setup Agents Based on if the Census Information is Being Used


  if use-census-data and which-region?  != "FLORIDA"
  [print "*** WARNING: Census Data is only available for Florida and will not be used for locations or decisions. ***"]

  ifelse use-census-data and which-region?  = "FLORIDA"
  [Create-Citizen-Agents-From-Census-Tracts];; creates agents based on census data and assigns them
  [Create-Citizen-Agent-Population];; creates the agents and distribtues them randomly or based on population density

  Create-Other-Agents;; Officials, Broadcasters and Aggregators are created

  Social-Network ;; defines the agents' social networks


end
@#$#@#$#@
GRAPHICS-WINDOW
229
18
1000
600
-1
-1
3.8
1
10
1
1
1
0
0
0
1
-100
100
-75
75
0
0
1
ticks
30.0

SLIDER
12
10
184
43
#citizen-agents
#citizen-agents
0
5000
350.0
1
1
NIL
HORIZONTAL

SLIDER
12
48
184
81
#broadcasters
#broadcasters
0
10
10.0
1
1
NIL
HORIZONTAL

SLIDER
13
86
185
119
#net-aggregators
#net-aggregators
0
10
10.0
1
1
NIL
HORIZONTAL

BUTTON
17
527
187
562
Show Network Connections
Show-Links
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
18
446
185
479
Run Simulation
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
18
491
187
524
go-once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
1083
32
1401
237
when they thought...
NIL
NIL
0.0
120.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 1 -16777216 true "set-histogram-num-bars 20" ";if ticks = 120 [\nset-plot-pen-interval 6\nhistogram [item 2 item 0 completed] of cit-ags with [not empty? completed and item 0 item 0 completed = \"evacuate\"]\n;        ]"

PLOT
1083
245
1399
464
watcher
NIL
NIL
0.0
120.0
-0.5
15.0
true
true
"clear-plot" ""
PENS
"life" 1.0 0 -16777216 true "" "if watching != 0 [plot [risk-life] of watching]"
"prop" 1.0 0 -11053225 true "" "if watching != 0 [plot [risk-property] of watching]"
"info +" 1.0 0 -7500403 true "" "if watching != 0 [plot [info-up] of watching]"
"info -" 1.0 0 -4539718 true "" "if watching != 0 [plot [info-down] of watching]"
"risk" 1.0 0 -5298144 true "" "if watching != 0 [plot last [risk-estimate] of watching]"

PLOT
1084
470
1399
670
risk function addittive
NIL
NIL
0.0
120.0
-0.5
15.0
true
true
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot risk-total"
"funct" 1.0 0 -7500403 true "" "plot risk-funct"
"error" 1.0 0 -2674135 true "" "plot risk-error"
"orders" 1.0 0 -955883 true "" "plot risk-orders"
"env" 1.0 0 -6459832 true "" "plot risk-env"
"pen-5" 1.0 0 -13791810 true "" "plot risk-surge"

SLIDER
14
161
186
194
earliest
earliest
12
78
78.0
3
1
NIL
HORIZONTAL

SLIDER
14
201
186
234
latest
latest
0
12
0.0
3
1
NIL
HORIZONTAL

SLIDER
14
242
186
275
wind-threshold
wind-threshold
70
130
116.0
1
1
NIL
HORIZONTAL

CHOOSER
13
285
185
330
which-storm?
which-storm?
"HARVEY" "WILMA" "WILMA_IDEAL" "CHARLEY_REAL" "CHARLEY_IDEAL" "CHARLEY_BAD" "IRMA" "MICHAEL"
7

SWITCH
16
124
186
157
distribute_population
distribute_population
1
1
-1000

SLIDER
14
680
107
713
forc-w
forc-w
0
2
1.37
.01
1
NIL
HORIZONTAL

SLIDER
15
645
107
678
evac-w
evac-w
0
4
0.62
.01
1
NIL
HORIZONTAL

SLIDER
14
716
107
749
envc-w
envc-w
0
6
1.0
.01
1
NIL
HORIZONTAL

SLIDER
14
758
186
791
network-distance
network-distance
0
50
50.0
5
1
NIL
HORIZONTAL

SLIDER
13
792
185
825
network-size
network-size
1
10
2.0
1
1
NIL
HORIZONTAL

SLIDER
9
833
298
866
citizen-to-census-population-ratio
citizen-to-census-population-ratio
0
10000
7000.0
500
1
NIL
HORIZONTAL

SWITCH
525
741
722
774
kids-under-18-factor
kids-under-18-factor
0
1
-1000

BUTTON
18
406
187
439
Setup Simulation
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
526
778
722
811
adults-over-65-factor
adults-over-65-factor
1
1
-1000

SLIDER
731
739
978
772
under-18-assessment-increase
under-18-assessment-increase
0.1
1
0.5
0.1
1
NIL
HORIZONTAL

SLIDER
730
778
976
811
over-65-assessment-decrease
over-65-assessment-decrease
0.1
1
0.4
0.1
1
NIL
HORIZONTAL

SLIDER
10
867
220
900
census-tract-min-pop
census-tract-min-pop
0
10000
5900.0
100
1
NIL
HORIZONTAL

SLIDER
10
902
220
935
census-tract-max-pop
census-tract-max-pop
0
10000
10000.0
100
1
NIL
HORIZONTAL

SWITCH
553
679
722
712
use-census-data
use-census-data
0
1
-1000

TEXTBOX
554
719
704
737
Census Factors In Use
11
0.0
1

SWITCH
527
815
722
848
limited-english-factor
limited-english-factor
1
1
-1000

SLIDER
730
817
977
850
limited-english-assessment-decrease
limited-english-assessment-decrease
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
730
853
978
886
foodstamps-assessment-decrease
foodstamps-assessment-decrease
0
1
1.0
0.1
1
NIL
HORIZONTAL

SWITCH
526
852
720
885
use-food-stamps-factor
use-food-stamps-factor
1
1
-1000

SWITCH
526
889
720
922
no-vehicle-factor
no-vehicle-factor
1
1
-1000

SLIDER
729
890
978
923
no-vehicle-assessment-modification
no-vehicle-assessment-modification
0
1
0.5
0.1
1
NIL
HORIZONTAL

SLIDER
728
928
978
961
no-internet-assessment-modification
no-internet-assessment-modification
0
1
1.0
0.1
1
NIL
HORIZONTAL

SWITCH
526
927
720
960
no-internet-factor
no-internet-factor
1
1
-1000

SLIDER
727
679
922
712
test-factor-proportion
test-factor-proportion
0
1
0.25
0.05
1
NIL
HORIZONTAL

BUTTON
1182
786
1320
819
PROFILER - Setup
profiler:start\nrepeat 3 [setup]\nprofiler:stop\nprint profiler:report\nprofiler:reset
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
16
582
190
627
where-to-place-legend?
where-to-place-legend?
"upper-right" "upper-left" "lower-right" "lower-left"
0

@#$#@#$#@
1. "setup" initializes the simulation.
2. "go-once" advances the simulation one time step.
3. "go" runs the simulation out to 120 time steps.


Coastline and urban center are on the lower half of the display, while the approaching hurricane (shown as a black & white target) is in the upper half of the display.


The storm track is shown with an orange line, swerve slider adjusts the curve of the storm track. The storm has size and intensity properties, defaulting to a large, high intensity storm for testing.


Citizen agents (color = blue) collect information about the storm from various sources (broadcasters, agencies, social network, personal enviromental cues), and run through a Protective Action Decision-Making process. When an agent chooses to evacuate, their color is set to orange.


## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

circle 3
true
0
Circle -16777216 false false 0 0 300

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
0
Rectangle -7500403 true true 151 225 180 285
Rectangle -7500403 true true 47 225 75 285
Rectangle -7500403 true true 15 75 210 225
Circle -7500403 true true 135 75 150
Circle -16777216 true false 165 76 116

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

storm
true
0
Circle -7500403 true true 44 44 212
Circle -16777216 true false 135 135 30
Polygon -7500403 true true 150 255 90 255 60 240 45 225 30 195 15 150 15 105 30 60 30 90 30 135 45 180
Polygon -7500403 true true 240 150 240 210 225 240 210 255 180 270 135 285 90 285 45 270 75 270 120 270 165 255
Polygon -7500403 true true 45 150 45 90 60 60 75 45 105 30 150 15 195 15 240 30 210 30 165 30 120 45
Polygon -7500403 true true 150 45 210 45 240 60 255 75 270 105 285 150 285 195 270 240 270 210 270 165 255 120

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment_test" repetitions="2" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="1.25"/>
      <value value="1.5"/>
      <value value="1.75"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_1-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_1-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_1-3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_1-3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_2-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_2-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_3-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_3-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_4" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_4"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_4-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_4-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_5" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_5"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_5-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_5-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_6" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_6"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_6-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_6-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_7" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_7"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_7-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_7-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_8" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_8"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_8-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_8-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_9" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_9"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="group_9-2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "group_9-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="timing_experiment" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "timing_experiment"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
      <value value="48"/>
      <value value="42"/>
      <value value="36"/>
      <value value="30"/>
      <value value="24"/>
      <value value="18"/>
      <value value="12"/>
      <value value="6"/>
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="census_experiment" repetitions="1000" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "census_experiment"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="charley_real" repetitions="1000" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "charley_real"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="charley_ideal" repetitions="1000" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "charley_ideal"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="wilma_real" repetitions="1000" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "wilma_real"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="93"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;WILMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="wilma_ideal" repetitions="1000" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "wilma_ideal"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="108.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;WILMA_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_original" repetitions="1" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "short-tests"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="1.25"/>
      <value value="1.5"/>
      <value value="1.75"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="1.5"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4.5"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind1" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind2" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind3" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind4" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind4"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind5" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind5"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind6" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind6"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind7" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind7"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind8" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind8"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind9" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind9"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind10" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind10"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind11" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind11"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind12" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind12"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind13" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind13"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind14" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind14"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind15" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind15"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind16" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind16"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind17" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind17"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind18" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind18"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind19" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind19"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_wind20" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-wind20"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="3"/>
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_test_network" repetitions="500" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test-network"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="5"/>
      <value value="15"/>
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
      <value value="5"/>
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="basic_experiment" repetitions="100" runMetricsEveryStep="true">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="15"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_181128_networks" repetitions="2" runMetricsEveryStep="false">
    <setup>load-gis
load-hurricane
load-forecasts
setup
set output-filename "exp-test"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_IDEAL&quot;"/>
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="15"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_under_5_1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-under5-effect1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_under_5_2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-under5-effect2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_under_5_3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-under5-effect3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_under_5_4" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-under5-effect4"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_under_5_5" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-under5-effect5"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_over_74_1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-over74-effect1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_over_74_2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-over74-effect2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.25"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_over_74_3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-over74-effect3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_over_74_4" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-over74-effect4"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.75"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20181219_cenusus_affects_over_74_5" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-over74-effect5"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.95"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190114_census_highpop_fn" repetitions="1000" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-under5-effect1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cit-ag-to-census-pop-ratio">
      <value value="5000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190117_over_74_all_1" repetitions="200" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-over74-all-1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.95"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190117_over_74_all_2" repetitions="200" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-test-over74-all-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_nocensus_distfalse1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-nocensus_distfalse1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_nocensus_distfalse2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-nocensus_distfalse2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_nocensus_distfalse3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-nocensus_distfalse3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_nocensus_disttrue1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-nocensus_distdisttrue1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_nocensus_disttrue2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-nocensus_distdisttrue2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_nocensus_disttrue3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-nocensus_distdisttrue3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census_over74_1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-over74-1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census_over74_2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-over74-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census_over74_3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-over74-3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census_under5_1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-under5-1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census_under5_2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-under5-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190130_Irma_census_under5_3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-under5-3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190306_Irma_census_under5_1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-under5-1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-under-5">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-over-74">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190306_Irma_census_under5_2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-under5-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-under-5">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-over-74">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190306_Irma_census_under5_3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-under5-3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-under-5">
      <value value="75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-over-74">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190306_Irma_census_over74_1" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-over74-1"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-under-5">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-over-74">
      <value value="25"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190306_Irma_census_over74_2" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-over74-2"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-under-5">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-over-74">
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190306_Irma_census_over74_3" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-census-over74-3"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-kids-under-5">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-5-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-adults-over-74">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-74-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-under-5">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-frequency-over-74">
      <value value="75"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190422_Irma_under18_factor_test" repetitions="25" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-factor-test"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-factor-proportion">
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.15"/>
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="0.75"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190422_Irma_over65" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-over65"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190422_Irma_internet" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-internet"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190422_Irma_limited_english" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-limenglish"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190422_Irma_novehicle" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-novehicle"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190422_Irma_foodstamps" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-foodstamps"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190422_Irma_all5" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-all5"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190422_Irma_under18_old" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-under18"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190723_Irma_under18" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190422-Irma-under18-wind"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="90"/>
      <value value="100"/>
      <value value="105"/>
      <value value="116"/>
      <value value="125"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190723_charley_real_new_cone" repetitions="50" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "20190723-charley-new-cone"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <enumeratedValueSet variable="census-tract-max-pop">
      <value value="10000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cit-ag-to-census-pop-ratio">
      <value value="7000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="test-factor-proportion">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;CHARLEY_REAL&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="census-tract-min-pop">
      <value value="5000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1.37"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="0.62"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190805_Irma_over65" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190805-Irma-over65"
set evac-filename "exp-irma-20190805-Irma-over65-evac"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190828_Irma" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190828-Irma"
set evac-filename "exp-irma-20190828-Irma-evac"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190828_Irma_networks" repetitions="20" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190828-Irma-networks"
set evac-filename "exp-irma-20190828-Irma-evac-networks"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="5"/>
      <value value="10"/>
      <value value="25"/>
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190828_Irma_over65" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190828-Irma-over65"
set evac-filename "exp-irma-20190828-Irma-evac-over65"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190828_Irma_under_18" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190828-Irma-under18"
set evac-filename "exp-irma-20190828-Irma-evac-under18"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190828_Irma_no_vehicle" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190828-Irma-novehicle"
set evac-filename "exp-irma-20190828-Irma-evac-novehicle"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190828_Irma_census_null" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190828-Irma-census-null"
set evac-filename "exp-irma-20190828-Irma-evac-census-null"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190828_Irma_no_census" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190828-Irma-nocensus"
set evac-filename "exp-irma-20190828-Irma-evac-nocensus"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_20190828_Irma_no_internet" repetitions="100" runMetricsEveryStep="false">
    <setup>load-gis-hpc
load-hurricane-hpc
load-forecasts-hpc
setup
set output-filename "exp-irma-20190828-Irma-nointernet"
set evac-filename "exp-irma-20190828-Irma-evac-nointernet"</setup>
    <go>go</go>
    <metric>new-last-records</metric>
    <metric>cit-ag-evac-records</metric>
    <enumeratedValueSet variable="kids-under-18-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="under-18-assessment-increase">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-factor">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-internet-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="limited-english-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="no-vehicle-assessment-modification">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="adults-over-65-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="over-65-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-food-stamps-factor">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="foodstamps-assessment-decrease">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="latest">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#net-aggregators">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="earliest">
      <value value="54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#broadcasters">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#citizen-agents">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wind_threshold">
      <value value="116"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-region?">
      <value value="&quot;FLORIDA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="which-storm?">
      <value value="&quot;IRMA&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="distribute_population">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="forc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evac-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="envc-w">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-distance">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-size">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-census-data">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
