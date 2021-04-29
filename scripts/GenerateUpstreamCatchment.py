from qgis.PyQt.QtCore import QCoreApplication, QVariant
from qgis.core import (QgsProcessing,
                       QgsField,
                       QgsFields,
                       QgsFeature,
                       QgsProcessingFeedback,
                       QgsFeatureSink,
                       QgsProcessingException,
                       QgsProcessingAlgorithm,
                       QgsProcessingParameterFeatureSink,
                       QgsProcessingParameterVectorLayer,
                       QgsProcessingParameterVectorDestination)
from qgis import processing

def findUpstreamCatchment(rivers, lowerBound, upperBound, context, feedback):
    feedback.pushInfo("lowerBound is {}, upperBound is {}".format(lowerBound,upperBound))
    return processing.run("qgis:extractbyexpression", {
            'INPUT': rivers,
            'EXPRESSION': "{} <= RSC_NUMNA AND {} >= RSC_NUMNA".format(lowerBound,upperBound),
            'OUTPUT': 'memory:'
        }, context=context, feedback=feedback)['OUTPUT']
        
def fixAndDissolveFeatures(input, context, feedback ):
    # run the input throuhg the fix geometries algorithm first
    fixed = processing.run("qgis:fixgeometries", {
        'INPUT': input,
        'OUTPUT': 'memory:'
    })['OUTPUT']
    return processing.run("qgis:dissolve", {
        'INPUT': fixed,
        'OUTPUT': 'memory:'
    }, context=context, feedback=feedback)['OUTPUT']
    

class UpstreamCatchmentGenerator(QgsProcessingAlgorithm):
    NETWORK = 'NETWORK'
    SITES = 'SITES'
    OUTPUT = 'OUTPUT'
    def tr(self, string):
        return QCoreApplication.translate('Processing', string)

    def createInstance(self):
        return UpstreamCatchmentGenerator()

    def name(self):
        return 'cfevupstreamcatchment'

    def displayName(self):
        return self.tr("Extract Upstream Catchment")

    def group(self):
        return self.tr('Network Analysis')

    def groupId(self):
        return 'networkanalysis'

    def shortHelpString(self):
        return self.tr("Generates a layer of upstream catchment polygons from a points layer")

    def initAlgorithm(self, config=None):
        self.addParameter(
            QgsProcessingParameterVectorLayer(
                self.NETWORK,
                self.tr('River network layer'),
                [QgsProcessing.TypeVectorPolygon]
            )
        )
        
        self.addParameter(
            QgsProcessingParameterVectorLayer(
                self.SITES,
                self.tr('Sites'),
                [QgsProcessing.TypeVectorPoint]
            )
        )
        
        self.addParameter(
            QgsProcessingParameterFeatureSink(
                self.OUTPUT,
                self.tr('Output layer')
            )
        )
        
    def processAlgorithm(self, parameters, context, feedback):
        sites = self.parameterAsLayer(parameters, self.SITES, context)
        if sites is None:
            raise QgsProcessingException(self.invalidSourceError(parameters, self.SITES))
            
        rivers = self.parameterAsLayer(parameters, self.NETWORK, context)
        if rivers is None:
            raise QgsProcessingException(self.invalidSourceError(parameters, self.NETWORK))
            
        fields = QgsFields()
        fields.append( QgsField("Site code",QVariant.String) )
        (sink, dest_id) = self.parameterAsSink(
            parameters,
            self.OUTPUT,
            context,
            fields,
            rivers.wkbType(),
            rivers.sourceCrs(),
            QgsFeatureSink.RegeneratePrimaryKey
        )
        if sink is None:
            raise QgsProcessingException(self.invalidSinkError(parameters, self.OUTPUT))
            
        upstreamFeatures = []
        total = sites.featureCount()
        nullFeedback=QgsProcessingFeedback()
        
        
        for current, feature in enumerate(sites.getFeatures()):
            feedback.pushInfo("processing feature {} of {}".format(current, total))
            feedback.setProgress( int( current * 100 / total ) )
            if feedback.isCanceled():
                break
            upstream = findUpstreamCatchment(rivers,feature.attribute("RSC_NUMNA"),feature.attribute("RSC_UNUMNA"), context, nullFeedback)
            upstreamDissolved = fixAndDissolveFeatures(upstream, context, nullFeedback )
            upstreamDissolvedFeature = next(upstreamDissolved.getFeatures())
            upstreamFeature = QgsFeature()
            upstreamFeature.setFields(fields)
            upstreamFeature.setAttribute("Site code", feature.attribute("Site code"))
            upstreamFeature.setGeometry( upstreamDissolvedFeature.geometry() )
            sink.addFeature( upstreamFeature )
            sink.flushBuffer()
            del upstream
            del upstreamDissolved

        return {self.OUTPUT: dest_id}
