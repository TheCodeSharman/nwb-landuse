#!/bin/bash

DATA_DIR=./data
DOWNLOADS_DIR=./downloads
TEMP_DIR=./tmp
GPKG_NAME=landuse_data_all.gpkg
[ ! -d $DOWNLOADS_DIR ] && mkdir $DOWNLOADS_DIR
[ ! -d $TEMP_DIR ] && mkdir $TEMP_DIR
PREFIX_SOURCE="https://listdata.thelist.tas.gov.au/opendata/data"
DATA_URIS=("LIST_LAND_USE_2002_BRS_STATEWIDE" "LIST_LAND_USE_2009_2010_BRS_STATEWIDE" "LIST_LAND_USE_2013_BRS_STATEWIDE" "LIST_LAND_USE_2015_BRS_STATEWIDE" "LIST_LAND_USE_2019_BRS_STATEWIDE")

make_lower() {
    echo $(echo $1 | tr '[:upper:]' '[:lower:]' | sed -e 's/brs/BRS/g')
}

download_data() {
    echo "Downloading source data from ${PREFIX_SOURCE}..."
    for file in ${DATA_URIS[@]}; do
        [ ! -f "${DOWNLOADS_DIR}/${file}.zip" ] && wget -O "${DOWNLOADS_DIR}/${file}.zip" "${PREFIX_SOURCE}/${file}.zip"
    done
}

unzip_data() {
    echo "Unzipping files..."
    for file in ${DATA_URIS[@]}; do
        [ ! -f "${TEMP_DIR}/$(make_lower $file).shp" ] && unzip -d ${TEMP_DIR} "${DOWNLOADS_DIR}/${file}.zip" -x *.gdb/* *.tab readme.txt
    done
    [ ! -f "${TEMP_DIR}/CFEVRiverSectionCatchments.shp" ] && unzip -d ${TEMP_DIR} "${DATA_DIR}/CFEVRiverSectionCatchments.zip"
}

layer_exists() {
    ogrinfo -sql "SELECT name FROM sqlite_master WHERE name = '$1'" ${GPKG_NAME} -q | grep "$1" > /dev/null
}

import_data() {
    echo "Importing shape files into geopackage..."
    update=""
    if [ -f ${GPKG_NAME} ]; then
        update="-update"
    fi
    for file in ${DATA_URIS[@]}; do 
        layer=$(make_lower $file)
        if ! layer_exists "${layer}"; then 
            echo "...${layer}"
            ogr2ogr -f GPKG ${GPKG_NAME} ${update} -nlt MULTIPOLYGON "${TEMP_DIR}/${layer}.shp"
        fi
        update="-update"
    done

    layer="nwbb to aclump"
    if ! layer_exists "${layer}"; then 
        echo "...${layer}"
        ogr2ogr -f GPG ${GPKG_NAME} ${update} "${DATA_DIR}/${layer}.csv"
    fi

    layer="CFEVRiverSectionCatchments"
    if ! layer_exists "${layer}"; then
        echo "...${layer}"
        ogr2ogr -f GPKG ${GPKG_NAME} ${update} -nlt MULTIPOLYGON "${TEMP_DIR}/${layer}.shp"
    fi
}

download_data
unzip_data
import_data
