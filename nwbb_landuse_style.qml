<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<qgis minScale="1e+08" styleCategories="AllStyleCategories" hasScaleBasedVisibilityFlag="0" version="3.18.1-Zürich" maxScale="0">
  <flags>
    <Identifiable>1</Identifiable>
    <Removable>1</Removable>
    <Searchable>1</Searchable>
    <Private>0</Private>
  </flags>
  <temporal mode="0" enabled="0" fetchMode="0">
    <fixedRange>
      <start></start>
      <end></end>
    </fixedRange>
  </temporal>
  <customproperties>
    <property key="WMSBackgroundLayer" value="false"/>
    <property key="WMSPublishDataSourceUrl" value="false"/>
    <property key="embeddedWidgets/count" value="0"/>
    <property key="identify/format" value="Value"/>
  </customproperties>
  <pipe>
    <provider>
      <resampling zoomedInResamplingMethod="nearestNeighbour" enabled="false" maxOversampling="2" zoomedOutResamplingMethod="nearestNeighbour"/>
    </provider>
    <rasterrenderer nodataColor="" type="paletted" alphaBand="-1" opacity="1" band="1">
      <rasterTransparency/>
      <minMaxOrigin>
        <limits>None</limits>
        <extent>WholeRaster</extent>
        <statAccuracy>Estimated</statAccuracy>
        <cumulativeCutLower>0.02</cumulativeCutLower>
        <cumulativeCutUpper>0.98</cumulativeCutUpper>
        <stdDevFactor>2</stdDevFactor>
      </minMaxOrigin>
      <colorPalette>
        <paletteEntry value="1" color="#d677a5" label="Natural" alpha="255"/>
        <paletteEntry value="2" color="#dacf54" label="Minimal use" alpha="255"/>
        <paletteEntry value="4" color="#7eefd5" label="Water" alpha="255"/>
        <paletteEntry value="5" color="#1fcc53" label="Forestry" alpha="255"/>
        <paletteEntry value="6" color="#a465cd" label="Forestry plantation" alpha="255"/>
        <paletteEntry value="7" color="#a6cc67" label="Arable farming" alpha="255"/>
        <paletteEntry value="8" color="#d23f3f" label="Intensive arable farming" alpha="255"/>
        <paletteEntry value="9" color="#3a1fd3" label="Pastoral farming" alpha="255"/>
        <paletteEntry value="10" color="#6e97f0" label="Intensive pastoral farming" alpha="255"/>
        <paletteEntry value="11" color="#63e649" label="Mining" alpha="255"/>
        <paletteEntry value="12" color="#d279cc" label="Residential and infrastructure" alpha="255"/>
        <paletteEntry value="13" color="#1cb7e2" label="Waste management" alpha="255"/>
        <paletteEntry value="14" color="#ed760e" label="Industrial" alpha="255"/>
        <paletteEntry value="15" color="#efc14c" label="Unknown" alpha="255"/>
      </colorPalette>
      <colorramp type="randomcolors" name="[source]">
        <Option/>
      </colorramp>
    </rasterrenderer>
    <brightnesscontrast gamma="1" contrast="0" brightness="0"/>
    <huesaturation colorizeRed="255" colorizeOn="0" colorizeBlue="128" grayscaleMode="0" colorizeGreen="128" saturation="0" colorizeStrength="100"/>
    <rasterresampler maxOversampling="2"/>
    <resamplingStage>resamplingFilter</resamplingStage>
  </pipe>
  <blendMode>0</blendMode>
</qgis>
