from qgis.PyQt.QtCore import ( QCoreApplication, QVariant,
                               QDate )
from qgis.core import (QgsProcessing,
                       QgsField,
                       QgsFields,
                       QgsFeatureRequest,
                       QgsFeatureSink,
                       QgsProcessingException,
                       QgsProcessingAlgorithm,
                       QgsProcessingParameterMultipleLayers,
                       QgsProcessingParameterVectorLayer,
                       QgsProcessingParameterRasterLayer,
                       QgsProcessingParameterFeatureSink,
                       QgsProcessingParameterString,  # added
                       QgsPointXY,
                       QgsDistanceArea,
                       QgsProject)
from qgis import processing


class HistogramCountToHectaresAlgorithm(QgsProcessingAlgorithm):
    HISTOGRAM = 'HISTOGRAM'
    RASTER = 'RASTER'
    HISTOGRAM_PREFIX = 'HISTOGRAM_PREFIX'
    OUTPUT = 'OUTPUT'

    def tr(self, string):
        return QCoreApplication.translate('Processing', string)

    def createInstance(self):
        return HistogramCountToHectaresAlgorithm()

    def name(self):
        return 'histogramcounttohectares'

    def displayName(self):
        return self.tr('Histogram Count to Hectares')

    def group(self):
        return self.tr(self.groupId())

    def groupId(self):
        return 'Upstream Analysis'

    def shortHelpString(self):
        return self.tr("Converts histogram into percent")

    def initAlgorithm(self, config=None):
        self.addParameter(
            QgsProcessingParameterVectorLayer(
                self.HISTOGRAM,
                self.tr('Landuse histogram layer'),
                [QgsProcessing.TypeVector]
            )
        )

        self.addParameter(
            QgsProcessingParameterRasterLayer(
                self.RASTER,
                self.tr('Raster layer')
            )
        )
        
        self.addParameter(
            QgsProcessingParameterString(
                self.HISTOGRAM_PREFIX,
                self.tr('Histogram field prefix'),
                defaultValue='HISTO_'
            )
        )
        
        self.addParameter(
            QgsProcessingParameterFeatureSink(
                self.OUTPUT,
                self.tr('Output layer')
            )
        )

    def processAlgorithm(self, parameters, context, feedback):
        raster = self.parameterAsRasterLayer(parameters, self.RASTER, context)
        histogram = self.parameterAsLayer(parameters, self.HISTOGRAM, context)
        if histogram is None:
            raise QgsProcessingException(self.invalidSourceError(parameters, self.HISTOGRAM))
            
        # Read prefix from parameter (fallback to 'HISTO_' if empty)
        hist_prefix = self.parameterAsString(parameters, self.HISTOGRAM_PREFIX, context)
        if not hist_prefix:
            hist_prefix = 'HISTO_'      
        histoFields = QgsFields()
        otherFields = QgsFields()
        for field in histogram.fields():
            if field.name().startswith(hist_prefix):
                histoFields.append(field)
            else:
                otherFields.append(field)

        out_fields = histogram.fields()
        for field in histoFields:
                out_fields.append(QgsField('HECTARES_' + field.name()[len(hist_prefix):], QVariant.Double))

        (sink, dest_id) = self.parameterAsSink(
            parameters,
            self.OUTPUT,
            context,
            out_fields,
            histogram.wkbType(),
            histogram.sourceCrs()
        )

        if sink is None:
            raise QgsProcessingException(self.invalidSinkError(parameters, self.OUTPUT))

        cellArea = rasterCellArea(raster)
        for feature in histogram.getFeatures():
            # Stop the algorithm if cancel button has been clicked
            if feedback.isCanceled():
                break

            attrs = feature.attributes()
            for field in histoFields:
                value = (feature[field.name()]*cellArea)/10000.0  # convert m² to hectares
                attrs.append(value)
                
            feature.setAttributes(attrs)
            sink.addFeature(feature)

        feedback.pushInfo(f"✅ Histogram conversion complete. Cell area: {cellArea} m²") 
        return {self.OUTPUT: dest_id}

def rasterCellArea(raster):
    """
    Calculate the area (in square meters) of a single raster cell.
    Uses the full raster extent to compute total area in meters (ellipsoidal when appropriate)
    then divides by the number of pixels (width * height).
    """
    if raster is None:
        raise QgsProcessingException("Raster layer is None")

    extent = raster.extent()
    width = raster.width()
    height = raster.height()

    if width == 0 or height == 0:
        raise QgsProcessingException("Raster has zero width or height")

    # Build polygon around the full extent (clockwise, closed)
    xMin = extent.xMinimum()
    yMin = extent.yMinimum()
    xMax = extent.xMaximum()
    yMax = extent.yMaximum()

    pts = [
        QgsPointXY(xMin, yMin),
        QgsPointXY(xMax, yMin),
        QgsPointXY(xMax, yMax),
        QgsPointXY(xMin, yMax),
        QgsPointXY(xMin, yMin),
    ]

    d = QgsDistanceArea()
    # Use raster CRS and project's transform context for correct measurements
    try:
        d.setSourceCrs(raster.crs(), QgsProject.instance().transformContext())
        d.setEllipsoidalMode(True)
        ellipsoid = raster.crs().ellipsoidAcronym()
        if ellipsoid:
            d.setEllipsoid(ellipsoid)
    except Exception:
        # If setting CRS/ellipsoid fails, continue; measurePolygon may still work or fallback will apply.
        pass

    total_area_m2 = None
    try:
        total_area_m2 = d.measurePolygon(pts)
        # measurePolygon may return negative for orientation; take abs
        if total_area_m2 is not None:
            total_area_m2 = abs(total_area_m2)
    except Exception:
        total_area_m2 = None

    # Fallback: compute area in CRS units (extent width * height)
    if not total_area_m2 or total_area_m2 <= 0:
        try:
            total_area_m2 = extent.width() * extent.height()
        except Exception:
            raise QgsProcessingException("Could not determine raster extent area")

    cell_area = float(total_area_m2) / float(width * height)
    return round( cell_area, 0)
