from qgis.PyQt.QtCore import ( QCoreApplication, QVariant,
                               QDate )
from qgis.core import (QgsProcessing,
                       QgsField,
                       QgsFeatureRequest,
                       QgsFeatureSink,
                       QgsProcessingException,
                       QgsProcessingAlgorithm,
                       QgsProcessingParameterMultipleLayers,
                       QgsProcessingParameterVectorLayer,
                       QgsProcessingParameterFeatureSink)
from qgis import processing


class HistogramPercent(QgsProcessingAlgorithm):
    HISTOGRAM = 'HISTOGRAM'
    OUTPUT = 'OUTPUT'

    def tr(self, string):
        return QCoreApplication.translate('Processing', string)

    def createInstance(self):
        return HistogramPercent()

    def name(self):
        return 'histogrampercent'

    def displayName(self):
        return self.tr('Histogram Percent')

    def group(self):
        return self.tr('NWBB Processing')

    def groupId(self):
        return 'nwbb-processing'

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
            QgsProcessingParameterFeatureSink(
                self.OUTPUT,
                self.tr('Output layer')
            )
        )

   

    def processAlgorithm(self, parameters, context, feedback):
    
        histogram = self.parameterAsLayer(parameters, self.HISTOGRAM, context)
        if histogram is None:
            raise QgsProcessingException(self.invalidSourceError(parameters, self.HISTOGRAM))
            
      
        HISTOGRAM_PREFIX = 'HISTO_'
      
        histoFields = []
        for field in histogram.fields():
            if field.name().startswith(HISTOGRAM_PREFIX):
                histoFields.append(field)
                
        newFields = histogram.fields()
        for field in histoFields:
            newFields.append(QgsField(field.name() + "_P",QVariant.Double))
            
        (sink, dest_id) = self.parameterAsSink(
            parameters,
            self.OUTPUT,
            context,
            newFields,
            histogram.wkbType(),
            histogram.sourceCrs()
        )

        if sink is None:
            raise QgsProcessingException(self.invalidSinkError(parameters, self.OUTPUT))

        for feature in histogram.getFeatures():
            # Stop the algorithm if cancel button has been clicked
            if feedback.isCanceled():
                break
            sum = 0
            for field in histoFields:
                sum+=feature[field.name()]
                
            feature.setFields( newFields, False)
            attrs = feature.attributes()
            for field in histoFields:
                value = (feature[field.name()]/sum)*100
                attrs.append(value)
                
            feature.setAttributes(attrs)
            sink.addFeature(feature)
            
        return {self.OUTPUT: dest_id}
