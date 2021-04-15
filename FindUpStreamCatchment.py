from qgis.PyQt.QtCore import QCoreApplication
from qgis.core import (QgsProcessing,
                       QgsFeatureSink,
                       QgsProcessingException,
                       QgsProcessingAlgorithm,
                       QgsProcessingParameterFeatureSource,
                       QgsProcessingParameterVectorLayer,
                       QgsProcessingParameterVectorDestination)
from qgis import processing

def findStartingCatchment(sites, rivers, context, feedback):
    return processing.run("qgis:extractbylocation", {
            'INPUT': rivers,
            'PREDICATE': [1],
            'INTERSECT': sites,
            'OUTPUT': 'memory:'
        }, context=context, feedback=feedback)['OUTPUT']
        
def findUpstreamCatchment(rivers, lowerBound, upperBound, context, feedback):
    feedback.pushInfo("lowerBound is {}, upperBound is {}".format(lowerBound,upperBound))
    return processing.run("qgis:extractbyexpression", {
            'INPUT': rivers,
            'EXPRESSION': "{} <= RSC_NUMNA AND {} >= RSC_NUMNA".format(lowerBound,upperBound),
            'OUTPUT': 'memory:'
        }, context=context, feedback=feedback)['OUTPUT']
        
def mergeVectorLayers(list, outputLayer, context, feedback):
    return processing.run("qgis:mergevectorlayers", {
        'LAYERS': list,
        'OUTPUT': outputLayer
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

class CfevUpstreamCatchment(QgsProcessingAlgorithm):
    NETWORK = 'NETWORK'
    SITES = 'SITES'
    OUTPUT = 'OUTPUT'
    def tr(self, string):
        return QCoreApplication.translate('Processing', string)

    def createInstance(self):
        return CfevUpstreamCatchment()

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
            QgsProcessingParameterVectorDestination(
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
            
        outputLayer = self.parameterAsOutputLayer(parameters, self.OUTPUT, context)
        if outputLayer is None:
            raise QgsProcessingException(self.invalidSinkError(parameters, self.OUTPUT))
            
        startingCatchments = findStartingCatchment(sites, rivers, context, feedback) 
        upstreamFeatures = []
        total = startingCatchments.featureCount()
        for current, feature in enumerate(startingCatchments.getFeatures()):
            feedback.pushInfo("processing feature {} of {}".format(current, total))
            feedback.setProgress( int( current * 100 / total ) )
            if feedback.isCanceled():
                break
            upstream = findUpstreamCatchment(rivers,feature.attribute("RSC_NUMNA"),feature.attribute("RSC_UNUMNA"), context, feedback)
            upstream = fixAndDissolveFeatures(upstream, context, feedback )
            upstreamFeatures.append(upstream)
        mergeVectorLayers(upstreamFeatures, outputLayer, context, feedback )

        return {self.OUTPUT: outputLayer}
