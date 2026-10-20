// Derived from autoLive2d, Copyright (c) 2026 Dongshan_Randeng, MIT.
// See LICENSE.autolive2d; adapted for locally installed Cubism Editor 5.3.04.
package autolive2d.bridge;

import com.live2d.cubism.doc.model.CModelSource;
import com.live2d.cubism.doc.model.exporter.CMocExportSetting;
import com.live2d.cubism.doc.model.exporter.CModelExportSettingDialogData;
import com.live2d.cubism.doc.model.exporter.CModelExportSettingDialogData.FormatVersion;

import com.live2d.cubism.doc.model.exporter.w;
import com.live2d.cubism.doc.model.drawable.TextureState;
import com.live2d.cubism.doc.model.id.CParameterId;
import com.live2d.cubism.doc.model.extension.textureInput.CTextureInputExtension;
import com.live2d.cubism.doc.model.interpolator.KeyformGridSource;
import com.live2d.cubism.doc.model.drawable.artMesh.CArtMeshForm;
import com.live2d.cubism.doc.model.drawable.artMesh.CArtMeshSource;
import com.live2d.cubism.doc.resources.CImageDocumentProjectEntry;
import com.live2d.cubism.doc.resources.CLayeredImage;
import com.live2d.cubism.doc.resources.g;
import com.live2d.cubism.doc.model.CModel;
import com.live2d.cubism.doc.model.ACParameterControllableSource;
import com.live2d.cubism.doc.model.texture.modelImage.CModelImage;
import com.live2d.cubism.doc.model.texture.textureAtlas.CTextureAtlas;
import com.live2d.cubism.doc.model.param.CParameterSource;
import com.live2d.cubism.process.psd.CEPsdImport_Import;
import com.live2d.graphics.filter.CubismStaticFilterLibrary;
import com.live2d.graphics.CWritableImage;
import com.live2d.graphics3d.rendering.RenderType;
import com.live2d.sdk.cubism.core.CubismMoc;
import com.live2d.sdk.cubism.core.CubismModel;
import com.live2d.sdk.cubism.core.Live2DCubismCore;
import com.live2d.type.CAffine;
import com.live2d.undo.GroupUndo;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import kotlin.Pair;
import org.jdom.Document;
import org.jdom.Element;
import org.jdom.input.SAXBuilder;

public final class PsdExportBridge {
  public static void main(String[] args) {
    Map<String, Object> result = new LinkedHashMap<>();
    String psdPath = args.length > 0 ? args[0] : "";
    String outputMoc3Path = args.length > 1 ? args[1] : "";
    String outputTextureDirPath = args.length > 2 ? args[2] : "";
    String bindingManifestPath = args.length > 3 ? args[3] : "";
    String progressPath = args.length > 4 ? args[4] : "";

    result.put("status", "error");
    result.put("vendorDir", "");
    result.put("manifestPath", "");
    result.put("psdPath", psdPath);
    result.put("outputMoc3Path", outputMoc3Path);
    result.put("texturePaths", List.of());
    result.put("javaVersion", System.getProperty("java.version", ""));
    result.put("moc3Written", false);
    result.put("progressPath", progressPath);

    try {
      File psdFile = new File(psdPath);
      File outputFile = new File(outputMoc3Path);
      File outputTextureDir = new File(outputTextureDirPath);
      outputFile.getParentFile().mkdirs();
      outputTextureDir.mkdirs();

      writeStage(progressPath, "init-filters");
      CubismStaticFilterLibrary.INSTANCE.initFilter();

      writeStage(progressPath, "open-psd");
      CImageDocumentProjectEntry entry = new CImageDocumentProjectEntry(psdFile);
      entry.open();
      g opened = entry.getOpenedImageDocument();
      if (opened == null) {
        throw new IllegalStateException("PSD openedImageDocument is null.");
      }

      writeStage(progressPath, "extract-layered-image");
      CLayeredImage layeredImage = opened.a();
      result.put("layeredImageName", layeredImage.getName());
      result.put("width", layeredImage.getWidth());
      result.put("height", layeredImage.getHeight());
      result.put("topLevelLayerCount", layeredImage.getChildren().size());

      writeStage(progressPath, "import-model");
      GroupUndo groupUndo = GroupUndo.Companion.a();
      CModelSource modelSource =
        CEPsdImport_Import.a.a(layeredImage, psdFile, (CEPsdImport_Import.a) Class.forName("com.live2d.cubism.process.psd.CEPsdImport_Import$a").getEnumConstants()[0], groupUndo);
      if (System.getProperty("mio.bindings") != null) MioBindings.apply(modelSource, Path.of(System.getProperty("mio.bindings")));
      result.put("importedParameterCount", modelSource.getAllParameters().size());
      result.put("importedPartCount", modelSource.getAllParts().size());
      result.put("importedVisiblePartCount", countVisibleParts(modelSource));
      result.put("importedSketchPartCount", countSketchParts(modelSource));
      result.put("importedDrawableCount", modelSource.getAllDrawables().size());
      result.put("importedArtMeshCount", modelSource.getAllArtMeshes().size());
      result.put("importedVisibleArtMeshCount", countVisibleArtMeshes(modelSource));
      result.put("importedArtMeshWithDefaultKeyformCount", countArtMeshesWithDefaultKeyform(modelSource));
      result.put("importedArtMeshWithTextureAtlasStateCount", countArtMeshesWithTextureState(modelSource, TextureState.TEXTURE_ATLAS));
      result.put("importedArtMeshWithModelImageStateCount", countArtMeshesWithTextureState(modelSource, TextureState.MODEL_IMAGE));
      result.put("importedArtMeshWithZeroPositionCount", countArtMeshesWithZeroPositions(modelSource));
      result.put("importedArtMeshWithZeroUvCount", countArtMeshesWithZeroUvs(modelSource));
      result.put("importedArtMeshWithZeroIndexCount", countArtMeshesWithZeroIndices(modelSource));
      result.put("importedParameterDebug", collectParameterDebug(modelSource));
      result.put("importedPartDebug", collectPartDebug(modelSource));
      result.put("importedArtMeshDebug", collectArtMeshDebug(modelSource));
      result.put("rawImageCount", modelSource.getTextureManager().getRawImages().size());
      result.put("modelImageGroupCount", modelSource.getTextureManager().getModelImageGroups().size());
      result.put("modelImageCount", modelSource.getTextureManager().getAllModelImages().size());
      result.put("textureAtlasCount", modelSource.getTextureManager().getTextureAtlases().size());
      result.put("textureInputModelImageMode", modelSource.getTextureManager().isTextureInputModelImageMode());

      if (bindingManifestPath != null && !bindingManifestPath.isBlank()) {
        writeStage(progressPath, "apply-strict-bindings");
        applyStrictBindings(modelSource, new File(bindingManifestPath));
      }

      writeStage(progressPath, "build-texture-atlases");
      ensureTextureAtlases(modelSource);
      result.put(
        "generatedTextureAtlasCount",
        modelSource.getTextureManager().getTextureAtlases().size()
      );

      writeStage(progressPath, "prepare-pre-export-state");
      modelSource.getTextureManager().changeModelTextureInput_toAtlas();
      modelSource.getTextureManager().getHandler().h();
      forceTextureStateToAtlasForBoundArtMeshes(modelSource);
      int atlasBoundArtMeshCount = countAtlasBoundArtMeshes(modelSource);
      result.put(
        "preExportAtlasBoundArtMeshCount",
        atlasBoundArtMeshCount
      );
      result.put(
        "preExportAtlasUnboundArtMeshCount",
        modelSource.getAllArtMeshes().size() - atlasBoundArtMeshCount
      );
      result.put(
        "preExportArtMeshWithTextureAtlasStateCount",
        countArtMeshesWithTextureState(modelSource, TextureState.TEXTURE_ATLAS)
      );
      result.put(
        "preExportArtMeshWithModelImageStateCount",
        countArtMeshesWithTextureState(modelSource, TextureState.MODEL_IMAGE)
      );

      writeStage(progressPath, "create-pre-export-instance");
      CModel instance = modelSource.createModelInstance(RenderType.PSD_EXPORT);
      result.put("preExportInstancePartCount", instance.getAllParts().size());
      result.put("preExportInstanceDrawableCount", instance.getAllDrawables().size());

      writeStage(progressPath, "save-intermediate-archive");
      File intermediateArchiveFile = new File(outputFile.getParentFile(), "Mio.cmo3");
      result.put("intermediateArchivePath", intermediateArchiveFile.getAbsolutePath());
      result.put(
        "intermediateArchiveSaved",
        modelSource.saveModel(intermediateArchiveFile, false)
      );

      writeStage(progressPath, "export-moc");
      ExportAttemptResult bestAttempt = exportWithFallbacks(modelSource, result);
      if (bestAttempt.error != null) {
        throw new IllegalStateException(bestAttempt.error);
      }
      byte[] mocBytes = bestAttempt.bytes;
      result.put("selectedVersion", bestAttempt.version);
      result.put("selectedExportFormat", bestAttempt.exportFormat);
      result.put("selectedConsistency", bestAttempt.consistency);
      result.put("selectedMocVersion", bestAttempt.mocVersion);
      result.put("selectedParameterCount", bestAttempt.parameterCount);
      result.put("selectedPartCount", bestAttempt.partCount);
      result.put("selectedDrawableCount", bestAttempt.drawableCount);

      writeStage(progressPath, "write-textures");
      result.put("texturePaths", writeTextureAtlases(modelSource, outputTextureDir));

      writeStage(progressPath, "write-moc");
      Files.write(outputFile.toPath(), mocBytes);

      result.put("status", "ok");
      result.put("moc3Written", true);
      result.put("moc3Size", mocBytes.length);
      writeStage(progressPath, "done");
    } catch (Throwable error) {
      Throwable root = unwrap(error);
      result.put("error", rootMessage(root));
      writeStage(progressPath, "error: " + rootMessage(root));
    }

    System.out.println(toJson(result));
    System.exit("ok".equals(result.get("status")) ? 0 : 1);
  }

  private static void ensureTextureAtlases(CModelSource modelSource) {
    if (!modelSource.getTextureManager().getTextureAtlases().isEmpty()) {
      return;
    }

    final int atlasSize = 4096;
    int atlasIndex = 0;
    int cursorX = 0;
    int cursorY = 0;
    int rowHeight = 0;
    CTextureAtlas currentAtlas = null;

    for (CModelImage modelImage : modelSource.getTextureManager().getAllModelImages()) {
      int imageWidth = modelImage.getWidth();
      int imageHeight = modelImage.getHeight();

      if (imageWidth <= 0 || imageHeight <= 0) {
        throw new IllegalStateException(
          "Model image has invalid dimensions: " + modelImage.getName()
        );
      }

      if (imageWidth > atlasSize || imageHeight > atlasSize) {
        throw new IllegalStateException(
          "Model image exceeds atlas size limit: " + modelImage.getName()
        );
      }

      if (currentAtlas == null || cursorX + imageWidth > atlasSize) {
        cursorX = 0;
        cursorY += rowHeight;
        rowHeight = 0;
      }

      if (currentAtlas == null || cursorY + imageHeight > atlasSize) {
        currentAtlas = new CTextureAtlas(
          modelSource,
          String.format("texture_%02d", atlasIndex),
          atlasSize,
          atlasSize
        );
        modelSource.getTextureManager().addTextureAtlas(currentAtlas, -1);
        atlasIndex += 1;
        cursorX = 0;
        cursorY = 0;
        rowHeight = 0;
      }

      CAffine modelImageLocalToAtlasTransform = new CAffine();
      modelImageLocalToAtlasTransform.translate((float) cursorX, (float) cursorY);

      CTextureAtlas.ModelImageEntry entry = new CTextureAtlas.ModelImageEntry(
        currentAtlas,
        modelImage.getGuid(),
        modelImageLocalToAtlasTransform
      );
      entry.setup();
      currentAtlas.getModelImages().add(entry);

      cursorX += imageWidth;
      rowHeight = Math.max(rowHeight, imageHeight);
    }
  }

  private static int countAtlasBoundArtMeshes(CModelSource modelSource) {
    int count = 0;
    for (var artMesh : modelSource.getAllArtMeshes()) {
      CTextureInputExtension textureInputExtension = artMesh.getTextureInputExtension();
      if (
        textureInputExtension != null &&
        textureInputExtension.getTextureAtlasInput() != null &&
        textureInputExtension.getTextureAtlasInput().getTextureAtlasGuid() != null
      ) {
        count += 1;
      }
    }
    return count;
  }

  private static int countVisibleParts(CModelSource modelSource) {
    int count = 0;
    for (var part : modelSource.getAllParts()) {
      if (part.isVisible()) {
        count += 1;
      }
    }
    return count;
  }

  private static int countSketchParts(CModelSource modelSource) {
    int count = 0;
    for (var part : modelSource.getAllParts()) {
      if (part.isSketch()) {
        count += 1;
      }
    }
    return count;
  }

  private static int countVisibleArtMeshes(CModelSource modelSource) {
    int count = 0;
    for (var artMesh : modelSource.getAllArtMeshes()) {
      if (artMesh.isVisible()) {
        count += 1;
      }
    }
    return count;
  }

  private static int countArtMeshesWithDefaultKeyform(CModelSource modelSource) {
    int count = 0;
    for (var artMesh : modelSource.getAllArtMeshes()) {
      if (artMesh.getDefaultKeyForm() != null) {
        count += 1;
      }
    }
    return count;
  }

  private static int countArtMeshesWithTextureState(
    CModelSource modelSource,
    TextureState textureState
  ) {
    int count = 0;
    for (var artMesh : modelSource.getAllArtMeshes()) {
      if (artMesh.getTextureState() == textureState) {
        count += 1;
      }
    }
    return count;
  }

  private static int countArtMeshesWithZeroPositions(CModelSource modelSource) {
    int count = 0;
    for (var artMesh : modelSource.getAllArtMeshes()) {
      float[] positions = artMesh.getPositions();
      if (positions == null || positions.length == 0) {
        count += 1;
      }
    }
    return count;
  }

  private static int countArtMeshesWithZeroUvs(CModelSource modelSource) {
    int count = 0;
    for (var artMesh : modelSource.getAllArtMeshes()) {
      float[] uvs = artMesh.getUvs();
      if (uvs == null || uvs.length == 0) {
        count += 1;
      }
    }
    return count;
  }

  private static int countArtMeshesWithZeroIndices(CModelSource modelSource) {
    int count = 0;
    for (var artMesh : modelSource.getAllArtMeshes()) {
      int[] indices = artMesh.getIndices();
      if (indices == null || indices.length == 0) {
        count += 1;
      }
    }
    return count;
  }

  private static List<Map<String, Object>> collectParameterDebug(CModelSource modelSource) {
    List<Map<String, Object>> debug = new ArrayList<>();
    for (var parameter : modelSource.getAllParameters()) {
      Map<String, Object> item = new LinkedHashMap<>();
      item.put("id", parameter.getId().toString());
      item.put("name", parameter.getName());
      item.put("minValue", parameter.getMinValue());
      item.put("defaultValue", parameter.getDefaultValue());
      item.put("maxValue", parameter.getMaxValue());
      debug.add(item);
      if (debug.size() >= 32) {
        break;
      }
    }
    return debug;
  }

  private static List<Map<String, Object>> collectPartDebug(CModelSource modelSource) {
    List<Map<String, Object>> debug = new ArrayList<>();
    for (var part : modelSource.getAllParts()) {
      Map<String, Object> item = new LinkedHashMap<>();
      item.put("id", part.getId().toString());
      item.put("localName", part.getLocalName());
      item.put("parentName", part.getParent() == null ? "" : part.getParent().getLocalName());
      debug.add(item);
      if (debug.size() >= 64) {
        break;
      }
    }
    return debug;
  }

  private static List<Map<String, Object>> collectArtMeshDebug(CModelSource modelSource) {
    List<Map<String, Object>> debug = new ArrayList<>();
    for (var artMesh : modelSource.getAllArtMeshes()) {
      Map<String, Object> item = new LinkedHashMap<>();
      item.put("id", artMesh.getId().toString());
      item.put("localName", artMesh.getLocalName());
      item.put(
        "parentName",
        artMesh.getParent() == null ? "" : artMesh.getParent().getLocalName()
      );
      item.put("parentChain", collectParentChain(artMesh));
      item.put("keyformCount", artMesh.getKeyforms().size());
      debug.add(item);
      if (debug.size() >= 64) {
        break;
      }
    }
    return debug;
  }

  private static List<String> collectParentChain(com.live2d.cubism.doc.model.ACParameterControllableSource source) {
    List<String> chain = new ArrayList<>();
    var current = source.getParent();
    while (current != null) {
      chain.add(current.getLocalName());
      current = current.getParent();
    }
    return chain;
  }

  private static void applyStrictBindings(CModelSource modelSource, File manifestFile)
    throws Exception {
    if (!manifestFile.isFile()) {
      throw new IllegalStateException("Binding manifest does not exist: " + manifestFile.getAbsolutePath());
    }

    Map<String, CArtMeshSource> artMeshByPath = new HashMap<>();
    for (var artMesh : modelSource.getAllArtMeshes()) {
      artMeshByPath.put(buildImportedPath(artMesh), artMesh);
    }

    SAXBuilder saxBuilder = new SAXBuilder();
    Document document = saxBuilder.build(manifestFile);
    Element root = document.getRootElement();
    for (Object parameterElementObject : root.getChildren("Parameter")) {
      applyStrictBindingParameter(
        modelSource,
        artMeshByPath,
        (Element) parameterElementObject
      );
    }

    modelSource.updateParamInstance(true);
  }

  private static void applyStrictBindingParameter(
    CModelSource modelSource,
    Map<String, CArtMeshSource> artMeshByPath,
    Element parameterElement
  ) {
    String parameterId = parameterElement.getAttributeValue("id", "");
    if (parameterId.isBlank()) {
      throw new IllegalStateException("Binding parameter is missing id.");
    }

    CParameterSource parameterSource =
      modelSource.getParameterSourceSet().get(new CParameterId(parameterId));
    if (parameterSource == null) {
      throw new IllegalStateException("Model source is missing parameter: " + parameterId);
    }

    List<Float> keyValues = new ArrayList<>();
    for (Object keyElementObject : parameterElement.getChildren("Key")) {
      Element keyElement = (Element) keyElementObject;
      keyValues.add(Float.parseFloat(keyElement.getAttributeValue("value")));
    }

    for (Object targetElementObject : parameterElement.getChildren("Target")) {
      Element targetElement = (Element) targetElementObject;
      String mode = targetElement.getAttributeValue("mode", "source-swap");
      if ("affine-transform".equals(mode)) {
        String targetPath = targetElement.getAttributeValue("relativeDrawablePath", "");
        if (targetPath.isBlank()) {
          throw new IllegalStateException("Affine binding target is missing relativeDrawablePath for parameter: " + parameterId);
        }
        CArtMeshSource artMeshSource = artMeshByPath.get(targetPath);
        if (artMeshSource == null) {
          throw new IllegalStateException("Unable to resolve affine binding drawable: " + targetPath);
        }
        applyDrawableAffineBinding(modelSource, artMeshSource, parameterSource, keyValues, targetElement);
        continue;
      }
      for (Object stateElementObject : targetElement.getChildren("State")) {
        Element stateElement = (Element) stateElementObject;
        String sourcePath = stateElement.getAttributeValue("sourcePath", "");
        if (sourcePath.isBlank()) {
          throw new IllegalStateException("Binding state is missing sourcePath for parameter: " + parameterId);
        }
        CArtMeshSource artMeshSource = artMeshByPath.get(sourcePath);
        if (artMeshSource == null) {
          throw new IllegalStateException("Unable to resolve bound drawable: " + sourcePath);
        }
        float activeKeyValue = Float.parseFloat(stateElement.getAttributeValue("keyValue"));
        applyDrawableOpacityBinding(modelSource, artMeshSource, parameterSource, keyValues, activeKeyValue);
      }
    }
  }

  private static void applyDrawableAffineBinding(
    CModelSource modelSource,
    CArtMeshSource artMeshSource,
    CParameterSource parameterSource,
    List<Float> keyValues,
    Element targetElement
  ) {
    CArtMeshForm defaultForm = artMeshSource.getDefaultKeyForm();
    if (defaultForm == null) {
      throw new IllegalStateException("Drawable is missing default keyform: " + buildImportedPath(artMeshSource));
    }

    Map<Float, Element> stateByKeyValue = new HashMap<>();
    for (Object stateElementObject : targetElement.getChildren("State")) {
      Element stateElement = (Element) stateElementObject;
      stateByKeyValue.put(Float.parseFloat(stateElement.getAttributeValue("keyValue")), stateElement);
    }

    while (artMeshSource.getKeyforms().size() > 1) {
      artMeshSource.getKeyforms().remove(artMeshSource.getKeyforms().size() - 1);
    }

    List<com.live2d.type.CFormGuid> formGuids = new ArrayList<>();
    float defaultKeyValue = parameterSource.getDefaultValue();
    for (float keyValue : keyValues) {
      Element stateElement = stateByKeyValue.get(keyValue);
      CArtMeshForm form;
      if (areEqual(keyValue, defaultKeyValue)) {
        form = defaultForm;
      } else {
        form = (CArtMeshForm) defaultForm.deepCopy(new com.live2d.core.a());
        form.setGuid(new com.live2d.type.CFormGuid());
        form.setName(artMeshSource.getLocalName() + "_" + keyValue);
        artMeshSource.getKeyforms().add(form);
      }
      applyAffineState(defaultForm, form, stateElement);
      formGuids.add(form.getGuid());
    }

    KeyformGridSource keyformGridSource = new KeyformGridSource(artMeshSource);
    List<Pair<com.live2d.type.CParameterGuid, float[]>> parameterKeys = new ArrayList<>();
    parameterKeys.add(new Pair<>(parameterSource.getGuid(), toFloatArray(keyValues)));
    try {
      keyformGridSource
        .getClass()
        .getMethod("import", CModelSource.class, List.class, List.class)
        .invoke(keyformGridSource, modelSource, parameterKeys, formGuids);
    } catch (ReflectiveOperationException error) {
      throw new IllegalStateException("Failed to invoke KeyformGridSource.import", error);
    }
    artMeshSource.setKeyformGridSource(keyformGridSource);
  }

  private static void applyDrawableOpacityBinding(
    CModelSource modelSource,
    CArtMeshSource artMeshSource,
    CParameterSource parameterSource,
    List<Float> keyValues,
    float activeKeyValue
  ) {
    CArtMeshForm defaultForm = artMeshSource.getDefaultKeyForm();
    if (defaultForm == null) {
      throw new IllegalStateException("Drawable is missing default keyform: " + buildImportedPath(artMeshSource));
    }

    while (artMeshSource.getKeyforms().size() > 1) {
      artMeshSource.getKeyforms().remove(artMeshSource.getKeyforms().size() - 1);
    }

    List<com.live2d.type.CFormGuid> formGuids = new ArrayList<>();
    float defaultKeyValue = parameterSource.getDefaultValue();
    for (float keyValue : keyValues) {
      CArtMeshForm form;
      if (areEqual(keyValue, defaultKeyValue)) {
        form = defaultForm;
      } else {
        form = (CArtMeshForm) defaultForm.deepCopy(new com.live2d.core.a());
        form.setGuid(new com.live2d.type.CFormGuid());
        form.setName(artMeshSource.getLocalName() + "_" + keyValue);
        artMeshSource.getKeyforms().add(form);
      }
      form.setOpacity(areEqual(keyValue, activeKeyValue) ? 1f : 0f);
      formGuids.add(form.getGuid());
    }

    KeyformGridSource keyformGridSource = new KeyformGridSource(artMeshSource);
    List<Pair<com.live2d.type.CParameterGuid, float[]>> parameterKeys = new ArrayList<>();
    parameterKeys.add(new Pair<>(parameterSource.getGuid(), toFloatArray(keyValues)));
    try {
      keyformGridSource
        .getClass()
        .getMethod("import", CModelSource.class, List.class, List.class)
        .invoke(keyformGridSource, modelSource, parameterKeys, formGuids);
    } catch (ReflectiveOperationException error) {
      throw new IllegalStateException("Failed to invoke KeyformGridSource.import", error);
    }
    artMeshSource.setKeyformGridSource(keyformGridSource);
  }

  private static void applyAffineState(
    CArtMeshForm defaultForm,
    CArtMeshForm form,
    Element stateElement
  ) {
    float[] defaultPositions = defaultForm.getPositions();
    float[] positions = java.util.Arrays.copyOf(defaultPositions, defaultPositions.length);
    float pivotX = parseFloatAttribute(stateElement, "pivotX", calculatePivotX(defaultPositions));
    float pivotY = parseFloatAttribute(stateElement, "pivotY", calculatePivotY(defaultPositions));
    float translateX = parseFloatAttribute(stateElement, "translateX", 0f);
    float translateY = parseFloatAttribute(stateElement, "translateY", 0f);
    float scaleX = parseFloatAttribute(stateElement, "scaleX", 1f);
    float scaleY = parseFloatAttribute(stateElement, "scaleY", 1f);
    float rotationDeg = parseFloatAttribute(stateElement, "rotationDeg", 0f);
    float opacity = parseFloatAttribute(stateElement, "opacity", defaultForm.getOpacity());
    double radians = Math.toRadians(rotationDeg);
    float cos = (float) Math.cos(radians);
    float sin = (float) Math.sin(radians);

    for (int index = 0; index < positions.length; index += 2) {
      float x = defaultPositions[index];
      float y = defaultPositions[index + 1];
      float localX = (x - pivotX) * scaleX;
      float localY = (y - pivotY) * scaleY;
      float rotatedX = localX * cos - localY * sin;
      float rotatedY = localX * sin + localY * cos;
      positions[index] = rotatedX + pivotX + translateX;
      positions[index + 1] = rotatedY + pivotY + translateY;
    }

    form.setPositions(positions);
    form.setOpacity(opacity);
  }

  private static String buildImportedPath(ACParameterControllableSource source) {
    List<String> segments = new ArrayList<>();
    segments.add(source.getLocalName());
    var current = source.getParent();
    while (current != null) {
      if (!"Root Part".equals(current.getLocalName())) {
        segments.add(current.getLocalName());
      }
      current = current.getParent();
    }
    Collections.reverse(segments);
    return String.join("/", segments);
  }

  private static float[] toFloatArray(List<Float> values) {
    float[] array = new float[values.size()];
    for (int index = 0; index < values.size(); index += 1) {
      array[index] = values.get(index);
    }
    return array;
  }

  private static boolean areEqual(float left, float right) {
    return Math.abs(left - right) < 0.0001f;
  }

  private static float parseFloatAttribute(
    Element element,
    String attributeName,
    float fallback
  ) {
    if (element == null) {
      return fallback;
    }
    String raw = element.getAttributeValue(attributeName, "");
    if (raw == null || raw.isBlank()) {
      return fallback;
    }
    return Float.parseFloat(raw);
  }

  private static float calculatePivotX(float[] positions) {
    float minX = Float.POSITIVE_INFINITY;
    float maxX = Float.NEGATIVE_INFINITY;
    for (int index = 0; index < positions.length; index += 2) {
      minX = Math.min(minX, positions[index]);
      maxX = Math.max(maxX, positions[index]);
    }
    return (minX + maxX) * 0.5f;
  }

  private static float calculatePivotY(float[] positions) {
    float minY = Float.POSITIVE_INFINITY;
    float maxY = Float.NEGATIVE_INFINITY;
    for (int index = 1; index < positions.length; index += 2) {
      minY = Math.min(minY, positions[index]);
      maxY = Math.max(maxY, positions[index]);
    }
    return (minY + maxY) * 0.5f;
  }

  private static void forceTextureStateToAtlasForBoundArtMeshes(CModelSource modelSource) {
    for (var artMesh : modelSource.getAllArtMeshes()) {
      CTextureInputExtension textureInputExtension = artMesh.getTextureInputExtension();
      if (
        textureInputExtension != null &&
        textureInputExtension.getTextureAtlasInput() != null &&
        textureInputExtension.getTextureAtlasInput().getTextureAtlasGuid() != null
      ) {
        artMesh.setTextureState(TextureState.TEXTURE_ATLAS);
      }
    }
  }

  private static List<String> writeTextureAtlases(
    CModelSource modelSource,
    File outputTextureDir
  ) {
    List<String> texturePaths = new ArrayList<>();
    int atlasIndex = 0;

    for (CTextureAtlas atlas : modelSource.getTextureManager().getTextureAtlases()) {
      atlas.updateTexture(true, true, null);
      if (atlas.getCachedAtlasImage() == null) {
        throw new IllegalStateException("Texture atlas cache image is null: " + atlas.getName());
      }

      CWritableImage writableImage = atlas.getCachedAtlasImage().getImageOrNullIfDisposed();
      if (writableImage == null) {
        writableImage = atlas.getCachedAtlasImage().getImage();
      }
      if (writableImage == null) {
        throw new IllegalStateException("Texture atlas writable image is null: " + atlas.getName());
      }

      File textureFile = new File(
        outputTextureDir,
        String.format("texture_%02d.png", atlasIndex)
      );
      writableImage.writeImage(textureFile);
      texturePaths.add(textureFile.getAbsolutePath());
      atlasIndex += 1;
    }

    return texturePaths;
  }

  private static ExportAttemptResult exportWithFallbacks(
    CModelSource modelSource,
    Map<String, Object> result
  ) {
    List<Map<String, Object>> attempts = new ArrayList<>();
    ExportAttemptResult bestAttempt = null;

    FormatVersion[] versionsToTry = new FormatVersion[] { FormatVersion.VERSION_40 };

    for (FormatVersion version : versionsToTry) {
      ExportAttemptResult attempt = exportAttempt(modelSource, version);
      attempts.add(attempt.toMap());
      if (bestAttempt == null || isBetterAttempt(attempt, bestAttempt)) {
        bestAttempt = attempt;
      }
      if (attempt.error == null && attempt.drawableCount > 0) {
        break;
      }
    }

    result.put("exportAttempts", attempts);
    return bestAttempt == null ? ExportAttemptResult.failed("No export attempts were executed.") : bestAttempt;
  }

  private static ExportAttemptResult exportAttempt(
    CModelSource modelSource,
    FormatVersion version
  ) {
    try {
      CModelExportSettingDialogData dialogData = new CModelExportSettingDialogData();
      dialogData.setVersion(version);
      dialogData.setup(modelSource);
      dialogData.setExportInvisiblePart(true);
      dialogData.setExportSketchPart(true);
      dialogData.setExportInvisibleArtMesh(true);

      CMocExportSetting mocExportSetting = dialogData.toMocSetting();
      w exporter = new w();
      exporter.a(mocExportSetting);
      var exportResult = exporter.a(modelSource, null);
      byte[] mocBytes = toByteArray(exportResult.a());

      ExportAttemptResult attempt = validateExportedBytes(version.name(), mocExportSetting, mocBytes);
      attempt.bytes = mocBytes;
      return attempt;
    } catch (Throwable error) {
      Throwable root = unwrap(error);
      return ExportAttemptResult.failed(version.name(), rootMessage(root));
    }
  }

  private static ExportAttemptResult validateExportedBytes(
    String version,
    CMocExportSetting mocExportSetting,
    byte[] mocBytes
  ) {
    ExportAttemptResult attempt = new ExportAttemptResult();
    attempt.version = version;
    attempt.exportFormat = mocExportSetting.getExportFormat().name();
    attempt.bytes = mocBytes;
    attempt.moc3Size = mocBytes.length;
    attempt.consistency = Live2DCubismCore.hasMocConsistency(mocBytes);
    attempt.mocVersion = Live2DCubismCore.getMocVersion(mocBytes);

    try (CubismMoc moc = CubismMoc.instantiate(mocBytes)) {
      try (CubismModel model = moc.instantiateModel()) {
        attempt.parameterCount = model.getParameterViews().length;
        attempt.partCount = model.getPartViews().length;
        attempt.drawableCount = model.getDrawableViews().length;
      }
    } catch (Throwable error) {
      Throwable root = unwrap(error);
      attempt.error = rootMessage(root);
    }

    return attempt;
  }

  private static boolean isBetterAttempt(
    ExportAttemptResult candidate,
    ExportAttemptResult current
  ) {
    return scoreAttempt(candidate) > scoreAttempt(current);
  }

  private static int scoreAttempt(ExportAttemptResult attempt) {
    if (attempt == null) {
      return Integer.MIN_VALUE;
    }
    if (attempt.error != null) {
      return -1;
    }
    int score = 0;
    if (attempt.consistency) {
      score += 1_000_000;
    }
    score += attempt.drawableCount * 10_000;
    score += attempt.partCount * 100;
    score += attempt.parameterCount;
    return score;
  }

  private static byte[] toByteArray(List<Byte> bytes) {
    byte[] buffer = new byte[bytes.size()];
    for (int index = 0; index < bytes.size(); index += 1) {
      buffer[index] = bytes.get(index);
    }
    return buffer;
  }

  private static void writeStage(String progressPath, String stage) {
    if (progressPath == null || progressPath.isBlank()) {
      return;
    }
    try {
      Files.writeString(Path.of(progressPath), stage);
    } catch (Throwable ignored) {
    }
  }

  private static Throwable unwrap(Throwable error) {
    if (error instanceof java.lang.reflect.InvocationTargetException) {
      Throwable cause = ((java.lang.reflect.InvocationTargetException) error).getTargetException();
      return cause == null ? error : cause;
    }
    return error;
  }

  private static String rootMessage(Throwable error) {
    Throwable current = error;
    while (current.getCause() != null && current.getCause() != current) {
      current = current.getCause();
    }
    String message = current.getMessage();
    return message == null || message.isBlank()
      ? current.getClass().getName()
      : current.getClass().getName() + ": " + message;
  }

  private static String toJson(Object value) {
    if (value == null) {
      return "null";
    }
    if (value instanceof String) {
      return "\"" + escape((String) value) + "\"";
    }
    if (value instanceof Number || value instanceof Boolean) {
      return String.valueOf(value);
    }
    if (value instanceof Map) {
      StringBuilder builder = new StringBuilder();
      builder.append("{");
      boolean first = true;
      for (Object entryObject : ((Map<?, ?>) value).entrySet()) {
        Map.Entry<?, ?> entry = (Map.Entry<?, ?>) entryObject;
        if (!first) {
          builder.append(",");
        }
        first = false;
        builder.append(toJson(String.valueOf(entry.getKey())));
        builder.append(":");
        builder.append(toJson(entry.getValue()));
      }
      builder.append("}");
      return builder.toString();
    }
    if (value instanceof Iterable<?>) { List<String> items=new ArrayList<>();for(Object item:(Iterable<?>)value)items.add(toJson(item));return "["+String.join(",",items)+"]"; }
    if (value.getClass().isArray()) { List<String> items=new ArrayList<>();for(int i=0;i<java.lang.reflect.Array.getLength(value);i++)items.add(toJson(java.lang.reflect.Array.get(value,i)));return "["+String.join(",",items)+"]"; }
    return toJson(String.valueOf(value));
  }

  private static String escape(String value) {
    return value
      .replace("\\", "\\\\")
      .replace("\"", "\\\"")
      .replace("\r", "\\r")
      .replace("\n", "\\n")
      .replace("\t", "\\t");
  }

  private static final class ExportAttemptResult {
    String version = "";
    String exportFormat = "";
    byte[] bytes = new byte[0];
    boolean consistency = false;
    int mocVersion = -1;
    int parameterCount = 0;
    int partCount = 0;
    int drawableCount = 0;
    int moc3Size = 0;
    String error;

    static ExportAttemptResult failed(String error) {
      return failed("", error);
    }

    static ExportAttemptResult failed(String version, String error) {
      ExportAttemptResult attempt = new ExportAttemptResult();
      attempt.version = version;
      attempt.error = error;
      return attempt;
    }

    Map<String, Object> toMap() {
      Map<String, Object> data = new LinkedHashMap<>();
      data.put("version", version);
      if (exportFormat != null && !exportFormat.isBlank()) {
        data.put("exportFormat", exportFormat);
      }
      if (moc3Size > 0) {
        data.put("moc3Size", moc3Size);
      }
      data.put("consistency", consistency);
      if (mocVersion >= 0) {
        data.put("mocVersion", mocVersion);
      }
      data.put("parameterCount", parameterCount);
      data.put("partCount", partCount);
      data.put("drawableCount", drawableCount);
      if (error != null && !error.isBlank()) {
        data.put("error", error);
      }
      return data;
    }
  }
}
