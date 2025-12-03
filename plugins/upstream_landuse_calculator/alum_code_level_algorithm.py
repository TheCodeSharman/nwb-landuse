from qgis.PyQt.QtCore import QCoreApplication
from qgis.core import (QgsProcessing,
                       QgsProcessingAlgorithm,
                       QgsProcessingParameterRasterLayer,
                       QgsProcessingParameterEnum,
                       QgsProcessingOutputRasterLayer)
import processing
from osgeo import gdal

class AlumCodeLevelAlgorithm(QgsProcessingAlgorithm):
    
    INPUT_RASTER = 'INPUT_RASTER'
    ALUM_CODE_LEVEL = 'ALUM_CODE_LEVEL'
    OUTPUT_RASTER = 'OUTPUT_RASTER'

    def tr(self, string):
        return QCoreApplication.translate('AlumCodeLevelAlgorithm', string)
    def createInstance(self):
        return AlumCodeLevelAlgorithm()

    def name(self):
        return 'alumcodelevelalgorithm'

    def displayName(self):
        return self.tr('Alum Code Level Algorithm')

    def group(self):
        return self.tr(self.groupId())

    def groupId(self):
        return 'Raster Analysis'

    def shortHelpString(self):
        return self.tr("Rounds ALUM code rasters: Primary=1 digit, Secondary=2 digits, Tertiary=3 digits")

    def initAlgorithm(self, config=None):
        self.addParameter(
            QgsProcessingParameterRasterLayer(
                self.INPUT_RASTER,
                self.tr('Input raster')
            )
        )
        
        self.rounding_modes = ["Don't Process", 'Primary', 'Secondary']
        self.addParameter(
            QgsProcessingParameterEnum(
                self.ALUM_CODE_LEVEL,
                self.tr('Alum Code Level'),
                options=self.rounding_modes,
                defaultValue=2,  # Tertiary
                allowMultiple=False
            )
        )
        
        self.addOutput(
            QgsProcessingOutputRasterLayer(
                self.OUTPUT_RASTER,
                self.tr('Simplified raster')
            )
        )

    def processAlgorithm(self, parameters, context, feedback):
        raster = self.parameterAsRasterLayer(parameters, self.INPUT_RASTER, context)
        mode_idx = self.parameterAsEnum(parameters, self.ALUM_CODE_LEVEL, context)
        mode = self.rounding_modes[mode_idx]
        
        feedback.pushInfo(f"Using rounding mode: {mode}")
        
        # Native Round Raster with negative decimal places (Base=10)
        if mode == 'Primary':
            decimals = -2   # Rounds to 100s: 111→100, 663→600
        elif mode == 'Secondary':
            decimals = -1   # Rounds to 10s: 111→110, 663→660
        else:  # don't do any processing
            return {self.OUTPUT_RASTER: raster}
        
        params = {
            'INPUT': raster,
            'BASE': 10,              # Power of 10 rounding
            'DECIMAL_PLACES': decimals,    # Negative = truncate digits
            'OUTPUT': QgsProcessing.TEMPORARY_OUTPUT
        }
        
        rounded_raster = processing.run(
            "native:roundrastervalues",
            params,
            context=context,
            feedback=feedback,
            is_child_algorithm=True
        )['OUTPUT']
    
        feedback.pushInfo(f"✅ Native rounding complete: {decimals} decimal places (Base=10)")
        return {self.OUTPUT_RASTER: rounded_raster}
