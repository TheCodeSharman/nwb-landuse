#!/bin/bash

#
# NWBB Land use analysis script
#
# This script downloads data from public sources, and combines it with
# waterbug data sets in order to get an understanding of how land use changes
# over time have been impacting the health of waterways.
#
DATA_DIR=./data
DOWNLOADS_DIR=./downloads
TEMP_DIR=./tmp
GPKG_NAME=${DATA_DIR}/landuse_data_all.gpkg
[ ! -d $DOWNLOADS_DIR ] && mkdir $DOWNLOADS_DIR
[ ! -d $TEMP_DIR ] && mkdir $TEMP_DIR
PREFIX_SOURCE="https://listdata.thelist.tas.gov.au/opendata/data"
LANDUSE_LAYERS=( \
    "LIST_LAND_USE_2002_BRS_STATEWIDE" \
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
    [ ! -f "${TEMP_DIR}/CFEVRiverSectionCatchments.shp" ] && unzip -d ${TEMP_DIR} "${DOWNLOADS_DIR}/CFEVRiverSectionCatchments.zip"
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
        qgis_process run PrepareLayer.model3 -- LanduseLayer="${TEMP_DIR}/$(make_layer_name $layer).shp" \
            NWBBLanduseLookup="${DATA_DIR}/nwbb to alum.csv" \
            LUCODE=${field} "native:retainfields_1:Layer Output"="ogr:dbname=${GPKG_NAME} table=${layer}_gen" \
            >>prepare.log 2>&1
    fi
}

rasterise_layer() {
    layer=$1
    field=$2
    if [ ! -f "${DATA_DIR}/${layer}_${field}.tif" ]; then
        echo "...${layer}_${field}.tif"
        qgis_process run Rasterise.model3 -- Landuselayer="${GPKG_NAME}|layername=${layer}_gen" \
            Field=${field} "gdal:rasterize_1:Landuse raster"="${DATA_DIR}/${layer}_${field}.tif" \
            >>rasterise.log 2>&1
    fi
}

import_data() {
    echo "Importing shape files into geopackage..."
    update=""
    if [ -f ${GPKG_NAME} ]; then
        update="-update"
    fi
    layer="CFEVRiverSectionCatchments"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        ogr2ogr -f GPKG ${GPKG_NAME} ${update} -nlt MULTIPOLYGON "${TEMP_DIR}/${layer}.shp"
    fi
}

prepare_data() {
    echo "Preparing data..."
    prepare_layer "LIST_LAND_USE_2002_BRS_STATEWIDE" "CODE"
    prepare_layer "LIST_LAND_USE_2009_2010_BRS_STATEWIDE" "LU_CODE"
    prepare_layer "LIST_LAND_USE_2013_BRS_STATEWIDE" "LU_CODE"
    prepare_layer "LIST_LAND_USE_2015_BRS_STATEWIDE" "LU_CODE"
    prepare_layer "LIST_LAND_USE_2019_BRS_STATEWIDE" "LU_CODEN"
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

download_data
unzip_data
import_data
prepare_data
rasterise_data
