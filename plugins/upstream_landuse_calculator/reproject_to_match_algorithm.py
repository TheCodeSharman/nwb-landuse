from qgis.PyQt.QtCore import QCoreApplication
from qgis.core import (QgsProcessing,
                       QgsProcessingAlgorithm,
                       QgsProcessingParameterVectorLayer,
                       QgsProcessingParameterRasterLayer,
                       QgsProcessingOutputVectorLayer,
                       QgsCoordinateReferenceSystem)
import processing

class ReprojectToMatchAlgorithm(QgsProcessingAlgorithm):
    
    INPUT_VECTOR = 'LAYER_SOURCE'
    INPUT_RASTER = 'LAYER_MATCH'
    OUTPUT_VECTOR = 'OUTPUT_VECTOR'

    def tr(self, string):
        return QCoreApplication.translate('ReprojectToMatch', string)

    def createInstance(self):
        return ReprojectToMatchAlgorithm()

    def name(self):
        return 'reprojecttomatch'

    def displayName(self):
        return self.tr('Reproject Vector to Match Raster CRS')

    def group(self):
        return self.tr('Vector projections')

    def groupId(self):
        return 'vectorprojections'

    def shortHelpString(self):
        return self.tr("Reprojects a vector layer to match the CRS of a reference raster layer.")

    def initAlgorithm(self, config=None):
        self.addParameter(
            QgsProcessingParameterVectorLayer(
                self.INPUT_VECTOR,
                self.tr('Vector layer to reproject (LAYER_SOURCE)'),
                [QgsProcessing.TypeVectorAnyGeometry]
            )
        )
        
        self.addParameter(
            QgsProcessingParameterRasterLayer(
                self.INPUT_RASTER,
                self.tr('Reference raster layer (LAYER_MATCH)'),
                optional=False
            )
        )
        
        self.addOutput(
            QgsProcessingOutputVectorLayer(
                self.OUTPUT_VECTOR,
                self.tr('Reprojected vector layer')
            )
        )

    def processAlgorithm(self, parameters, context, feedback):
        # Get input layers
        source_layer = self.parameterAsVectorLayer(parameters, self.INPUT_VECTOR, context)
        match_raster = self.parameterAsRasterLayer(parameters, self.INPUT_RASTER, context)
        
        if not source_layer or not match_raster:
            feedback.reportError("Invalid input layers")
            return {}
        
        # Get target CRS from reference raster
        target_crs = match_raster.crs()
        source_crs = source_layer.crs()
        
        feedback.pushInfo(f"Source CRS: {source_crs.authid()}")
        feedback.pushInfo(f"Target CRS: {target_crs.authid()}")
        
        # Skip reprojection if already matching
        if source_crs == target_crs:
            feedback.pushInfo("CRS already matches - returning original layer")
            return {self.OUTPUT_VECTOR: source_layer}
        
        # Reproject the vector layer
        params = {
            'INPUT': source_layer,
            'TARGET_CRS': target_crs,
            'OUTPUT': QgsProcessing.TEMPORARY_OUTPUT
        }
        
        reprojected_layer = processing.run(
            "native:reprojectlayer",
            params,
            context=context,
            feedback=feedback,
            is_child_algorithm=True
        )['OUTPUT']
        
        feedback.pushInfo("Reprojection completed successfully")
        return {self.OUTPUT_VECTOR: reprojected_layer}