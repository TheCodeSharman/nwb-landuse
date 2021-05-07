#!/bin/bash

#
# NWBB Land use analysis script
#
# This script downloads data from public sources, and combines it with
# waterbug data sets in order to get an understanding of how land use changes
# over time have been impacting the health of waterways.
#
PRODUCT_DIR=./products
SCRIPTS_DIR=./scripts
MODELS_DIR=./models
DATA_DIR=./data
VRT_DIR=./vrt
DOWNLOADS_DIR=./downloads
TEMP_DIR=./tmp
GPKG_NAME=${PRODUCT_DIR}/landuse_data_all.gpkg
[ ! -d $PRODUCT_DIR ] && mkdir $PRODUCT_DIR
[ ! -d $DOWNLOADS_DIR ] && mkdir $DOWNLOADS_DIR
[ ! -d $TEMP_DIR ] && mkdir $TEMP_DIR
PREFIX_SOURCE="https://listdata.thelist.tas.gov.au/opendata/data"
LANDUSE_LAYERS=( \
    "LIST_LAND_USE_2009_2010_BRS_STATEWIDE" \
    "LIST_LAND_USE_2013_BRS_STATEWIDE" \
    "LIST_LAND_USE_2015_BRS_STATEWIDE" \
    "LIST_LAND_USE_2019_BRS_STATEWIDE")

# Maps the upper case version of the file names in the lower case version of the layer name
# BRS is then reverted to upper case
make_layer_name() {
    echo $(echo $1 | tr '[:upper:]' '[:lower:]' | sed -e 's/brs/BRS/g')
}

download_data() {
    echo "Downloading source data from ${PREFIX_SOURCE}..."
    for file in ${LANDUSE_LAYERS[@]}; do
        [ ! -f "${DOWNLOADS_DIR}/${file}.zip" ] && wget -O "${DOWNLOADS_DIR}/${file}.zip" "${PREFIX_SOURCE}/${file}.zip"
    done
}

unzip_data() {
    echo "Unzipping files..."
    for file in ${LANDUSE_LAYERS[@]}; do
        [ ! -f "${TEMP_DIR}/$(make_layer_name $file).shp" ] && unzip -d ${TEMP_DIR} "${DOWNLOADS_DIR}/${file}.zip" -x *.gdb/* *.tab readme.txt
    done
    [ ! -f "${TEMP_DIR}/CFEVRiverSectionCatchments.shp" ] && unzip -d ${TEMP_DIR} "${DATA_DIR}/CFEVRiverSectionCatchments.zip"
}

layer_exists() {
    ogrinfo -sql "SELECT name FROM sqlite_master WHERE name = '$1'" ${GPKG_NAME} -q | grep "$1" > /dev/null
}

# The data files form the LIST change their format over time and we need to map the ALUM codes to
# broader categories to ensure the data is consistent across years, this is done by joining to the
# "nwbb to aclump.csv" file. 
#
# The PrepareLayer.model3 file is QGIS Processing model that performs this join and deals with
# changes in the naming of the LU_CODE column.
prepare_layer() {
    layer=$1
    field=$2
    if ! layer_exists "${layer}_gen"; then
        echo "...${layer}_gen"
        qgis_process run ${MODELS_DIR}/PrepareLayer.model3 -- LanduseLayer="${TEMP_DIR}/$(make_layer_name $layer).shp" \
            NWBBLanduseLookup="${DATA_DIR}/nwbb to alum.csv" \
            LUCODE=${field} "native:retainfields_1:Layer Output"="ogr:dbname=${GPKG_NAME} table=${layer}_gen" \
            >>${TEMP_DIR}/prepare.log 2>&1
    fi
}

rasterise_layer() {
    layer=$1
    field=$2
    if [ ! -f "${PRODUCT_DIR}/${layer}_${field}.tif" ]; then
        echo "...${layer}_${field}.tif"
        qgis_process run ${MODELS_DIR}/Rasterise.model3 -- Landuselayer="${GPKG_NAME}|layername=${layer}_gen" \
            Field=${field} "gdal:rasterize_1:Landuse raster"="${PRODUCT_DIR}/${layer}_${field}.tif" \
            >>${TEMP_DIR}/rasterise.log 2>&1
    fi
}

import_data() {
    echo "Importing shape files into geopackage..."
    layer="CFEVRiverSectionCatchments"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        qgis_process run "qgis:retainfields" -- INPUT="${TEMP_DIR}/${layer}.shp" FIELDS="RSC_ID;RSC_NUMNA;RSC_UNUMNA" \
            OUTPUT="ogr:dbname=${GPKG_NAME} table=${layer}" \
            >>${TEMP_DIR}/import.log 2>&1
    fi
    layer="site"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        ogr2ogr -f GPKG -update -t_srs EPSG:28355 -nln "${layer}" "${GPKG_NAME}" "${VRT_DIR}/site.vrt"
    fi

    layer="site_signal_score"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        ogr2ogr -f GPKG -update -nln "${layer}" "${GPKG_NAME}" "${VRT_DIR}/site_signal_score.vrt"
    fi

    layer="landuse_layer_date"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        ogr2ogr -f GPKG -update -nln "${layer}" "${GPKG_NAME}" "${DATA_DIR}/landuse to year.csv"
    fi
}

prepare_data() {
    echo "Preparing data..."
    prepare_layer "LIST_LAND_USE_2009_2010_BRS_STATEWIDE" "LU_CODE"
    prepare_layer "LIST_LAND_USE_2013_BRS_STATEWIDE" "LU_CODE"
    prepare_layer "LIST_LAND_USE_2015_BRS_STATEWIDE" "LU_CODE"
    prepare_layer "LIST_LAND_USE_2019_BRS_STATEWIDE" "LU_CODEN"

    layer="site_num"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        qgis_process run ${MODELS_DIR}/FindStartCatchment.model3 -- RiverNetwork="${GPKG_NAME}|layername=CFEVRiverSectionCatchments"  \
                Sites="${GPKG_NAME}|layername=site" \
                "native:joinattributesbylocation_1:Sites With Num"="ogr:dbname=${GPKG_NAME} table=${layer}" \
                >>${TEMP_DIR}/prepare.log 2>&1
    fi
}

rasterise_data() {
    echo "Generating impact rasters..."
    for layer in ${LANDUSE_LAYERS[@]}; do
        rasterise_layer ${layer} "nwbb_impact"
    done

    echo "Generating numcat rasters..."
    for layer in ${LANDUSE_LAYERS[@]}; do
        rasterise_layer ${layer} "nwbb_numcat"
    done

    echo "Generating landuse rasters..."
    for layer in ${LANDUSE_LAYERS[@]}; do
        rasterise_layer ${layer} "nwbb_landuse_code"
    done
}

generate_upstream() {
    echo "Generating upstream river catchments..."
    layer="upstream_catchment"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        qgis_process run ${MODELS_DIR}/UpstreamRivers.model3 -- RiverNetwork="${GPKG_NAME}|layername=CFEVRiverSectionCatchments"  \
            Sites="${GPKG_NAME}|layername=site_num" \
            "script:cfevupstreamcatchment_1:Upstream Catchments"="ogr:dbname=${GPKG_NAME} table=${layer}" \
            >>${TEMP_DIR}/upstream.log 2>&1
    fi
}


histogram_layer_input() {
    for layer in ${LANDUSE_LAYERS[@]}; do
         echo "HistogramLayers=${GPKG_NAME}|layername=${layer}_histogram "
    done
}

calculate_upstream_histogram() {
    echo "Calculating upstream histogram stats..."
    for layer in ${LANDUSE_LAYERS[@]}; do
        if ! layer_exists "${layer}_histogram"; then
            echo "...${layer}_histogram"
            qgis_process run ${MODELS_DIR}/Histogram.model3 -- Landuse="${PRODUCT_DIR}/${layer}_nwbb_landuse_code.tif"  \
                Upstream="${GPKG_NAME}|layername=upstream_catchment" \
                "script:histogrampercent_1:Histogram output"="ogr:dbname=${GPKG_NAME} table=${layer}_histogram" \
                >>${TEMP_DIR}/histogram.log 2>&1
        fi
    done

    echo "Merging histograms..."
    layer="landuse_histogram_date"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        qgis_process run ${MODELS_DIR}/MergeHistograms.model3 -- $(histogram_layer_input) \
                Layernametodate="${GPKG_NAME}|layername=landuse_layer_date" \
                "native:joinattributestable_1:Merged"="ogr:dbname=${GPKG_NAME} table=${layer}" \
                >>${TEMP_DIR}/histogram.log 2>&1
    fi

}

query_delta() {
    Y1=$1
    Y2=$2
    cat <<EOT
SELECT 
	y1.site_code,
    y1.geom,
    y1.X,
    y1.Y,
    y1.upstream_area,
	(julianday(y2.landuse_layer_date) - julianday(y1.landuse_layer_date)) as interval_landuse_days,
	(julianday(y2.sample_date) - julianday(y1.sample_date)) as interval_sample_date_days,
    (y2.signal_score- y1.signal_score) as signal_score_delta,
    (y2.signal_score_1- y1.signal_score_1) as signal_score_1_delta,
	(y2.HISTO_NODATA_P - y1.HISTO_NODATA_P) as HISTO_NODATA_P_DELTA,
	(y2.HISTO_1_P - y1.HISTO_1_P) as HISTO_1_P_DELTA,
	(y2.HISTO_2_P - y1.HISTO_2_P) as HISTO_2_P_DELTA,
	(y2.HISTO_4_P - y1.HISTO_4_P) as HISTO_4_P_DELTA,
	(y2.HISTO_5_P - y1.HISTO_5_P) as HISTO_5_P_DELTA,
	(y2.HISTO_6_P - y1.HISTO_6_P) as HISTO_6_P_DELTA,
	(y2.HISTO_7_P - y1.HISTO_7_P) as HISTO_7_P_DELTA,
	(y2.HISTO_8_P - y1.HISTO_8_P) as HISTO_8_P_DELTA,
	(y2.HISTO_9_P - y1.HISTO_9_P) as HISTO_9_P_DELTA,
	(y2.HISTO_10_P - y1.HISTO_10_P) as HISTO_10_P_DELTA,
	(y2.HISTO_11_P - y1.HISTO_11_P) as HISTO_11_P_DELTA,
	(y2.HISTO_12_P - y1.HISTO_12_P) as HISTO_12_P_DELTA,
	(y2.HISTO_13_P - y1.HISTO_13_P) as HISTO_13_P_DELTA,
	(y2.HISTO_14_P - y1.HISTO_14_P) as HISTO_14_P_DELTA,
	(y2.HISTO_15_P - y1.HISTO_15_P) as HISTO_15_P_DELTA
FROM
	(SELECT * FROM site_histogram WHERE strftime('%Y',landuse_layer_date) = '${Y1}') as y1
	JOIN (SELECT * FROM site_histogram WHERE strftime('%Y',landuse_layer_date) = '${Y2}') as y2 ON y1.site_code = y2.site_code
EOT
}


generate_site_to_landuse() {
    echo "Generating site to landuse layer..."
    layer="site_histogram"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        ogr2ogr -f GPKG -update -nln "${layer}" "${GPKG_NAME}" "${VRT_DIR}/site_histogram.vrt"
    fi
    layer="site_histogram_delta"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        ogr2ogr -f GPKG -update -append -nln "${layer}" "${GPKG_NAME}" -sql "$(query_delta "2012" "2021")" "${GPKG_NAME}"
        ogr2ogr -f GPKG -update -append -nln "${layer}" "${GPKG_NAME}" -sql "$(query_delta "2012" "2018")" "${GPKG_NAME}"
        ogr2ogr -f GPKG -update -append -nln "${layer}" "${GPKG_NAME}" -sql "$(query_delta "2012" "2014")" "${GPKG_NAME}"
        ogr2ogr -f GPKG -update -append -nln "${layer}" "${GPKG_NAME}" -sql "$(query_delta "2014" "2021")" "${GPKG_NAME}"
        ogr2ogr -f GPKG -update -append -nln "${layer}" "${GPKG_NAME}" -sql "$(query_delta "2014" "2018")" "${GPKG_NAME}"
        ogr2ogr -f GPKG -update -append -nln "${layer}" "${GPKG_NAME}" -sql "$(query_delta "2018" "2021")" "${GPKG_NAME}"
    fi
}

download_data
unzip_data
import_data
prepare_data
rasterise_data
generate_upstream
calculate_upstream_histogram
generate_site_to_landuse
