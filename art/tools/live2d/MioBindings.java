package autolive2d.bridge;

import com.live2d.cubism.doc.model.*;
import com.live2d.cubism.doc.model.drawable.artMesh.*;
import com.live2d.cubism.doc.model.deformer.rotation.*;
import com.live2d.cubism.doc.model.parts.*;
import com.live2d.cubism.doc.model.param.*;
import com.live2d.cubism.doc.model.id.*;
import com.live2d.cubism.doc.model.interpolator.KeyformGridSource;
import com.live2d.type.*;
import com.live2d.doc.CoordType;
import kotlin.Pair;
import org.json.simple.parser.JSONParser;
import java.nio.*;
import java.nio.file.*;
import java.util.*;

/** Authored Mio rig -> the installed Cubism model/export library.
 * No editor binary, license data or SDK library is copied or modified.
 * KeyformGridSource invocation follows autoLive2d's MIT Java bridge pattern.
 */
public final class MioBindings {
  private static CModelSource model;
  private static Map<String,CParameterSource> parameters;
  private static Map<String,CRotationDeformerSource> deformers;
  private static CoordType local,canvas;
  private static float number(Object value) { return ((Number)value).floatValue(); }
  private static float[] floats(List<?> values) {
    float[] result=new float[values.size()];for(int i=0;i<result.length;i++)result[i]=number(values.get(i));return result;
  }
  private static int[] ints(List<?> values) {
    int[] result=new int[values.size()];for(int i=0;i<result.length;i++)result[i]=((Number)values.get(i)).intValue();return result;
  }
  @SuppressWarnings("unchecked")
  public static void apply(CModelSource source,Path directory) throws Exception {
    model=source;
    Map<String,Object> data=(Map<String,Object>)new JSONParser().parse(Files.readString(directory.resolve("bake.json")));
    ByteBuffer positions=ByteBuffer.wrap(Files.readAllBytes(directory.resolve("forms.bin"))).order(ByteOrder.LITTLE_ENDIAN);
    local=(CoordType)CoordType.class.getMethod("b").invoke(null);
    canvas=(CoordType)CoordType.class.getMethod("c").invoke(null);
    source.getParameterSourceSet().clear();source.getRootParameterGroup().clear();parameters=new LinkedHashMap<>();deformers=new LinkedHashMap<>();
    for(Object object:(List<?>)data.get("parameters")) {
      Map<String,Object> spec=(Map<String,Object>)object;
      CParameterSource p=new CParameterSource();String id=(String)spec.get("id");
      p.setGuid(new CParameterGuid());p.setId(new CParameterId(id));p.setName(id);p.setMinValue(number(spec.get("min")));p.setMaxValue(number(spec.get("max")));p.setDefaultValue(number(spec.get("value")));
      p.setup(source);source.getParameterSourceSet().add(p,-1);source.getRootParameterGroup().add(p,-1);parameters.put(id,p);
    }
    source.getParameterSourceSet().updateMap();source.updateParamInstance(true);
    if(source.getAllParameters().size()!=parameters.size())throw new IllegalStateException("Parameter tree registration failed");
    rotation("Body","",new String[]{"ParamBodyAngleZ","ParamTorsoLift"},new float[][]{{-3,0,3},{0,5}});
    rotation("Head","Body",new String[]{"ParamAngleZ","ParamAngleX","ParamAngleY"},new float[][]{{-12,0,12},{-30,0,30},{-30,0,30}});
    float[] shoulderKeys=new float[45];for(int i=0;i<45;i++)shoulderKeys[i]=(i-22)/10f;
    rotation("ShoulderL","Body",new String[]{"ParamShoulderL"},new float[][]{shoulderKeys});
    rotation("ShoulderR","Body",new String[]{"ParamShoulderR"},new float[][]{shoulderKeys});
    rotation("ElbowL","ShoulderL",new String[]{"ParamElbowL"},new float[][]{{0,0.04f,1.6f}});
    rotation("ElbowR","ShoulderR",new String[]{"ParamElbowR"},new float[][]{{-2.2f,-0.04f,0,3.1f}});
    rotation("WristL","ElbowL",new String[]{"ParamWristL"},new float[][]{{-0.2f,0,0.2f}});
    rotation("WristR","ElbowR",new String[]{"ParamWristR"},new float[][]{{-0.2f,0,0.2f}});
    Map<String,CArtMeshSource> meshes=new HashMap<>();for(var mesh:source.getAllArtMeshes())meshes.put(mesh.getLocalName(),mesh);
    for(Object object:(List<?>)data.get("meshes")) {
      Map<String,Object> spec=(Map<String,Object>)object;String id=(String)spec.get("id");
      CArtMeshSource mesh=Objects.requireNonNull(meshes.get(id),"Missing imported mesh "+id);
      mesh.setVisible(true);mesh.setCulling(false);
      float[] oldPositions=mesh.getPositions().clone(),oldUvs=mesh.getUvs().clone();
      float[] base=floats((List<?>)spec.get("base")),uvs=new float[base.length];
      // The PSD importer includes one texel of padding and padded source-image
      // dimensions. Fit its existing affine mapping instead of assuming UVs.
      int x0=0,x1=-1,y1=-1;
      for(int i=1;i<oldPositions.length/2;i++) {
        if(Math.abs(oldPositions[2*i]-oldPositions[0])>0.01f && Math.abs(oldPositions[2*i+1]-oldPositions[1])<0.01f)x1=i;
        if(Math.abs(oldPositions[2*i+1]-oldPositions[1])>0.01f && Math.abs(oldPositions[2*i]-oldPositions[0])<0.01f)y1=i;
      }
      if(x1<0 || y1<0)throw new IllegalStateException("Imported PSD mesh has no axis-aligned UV basis: "+id);
      for(int i=0;i<base.length;i+=2) {
        float tx=(base[i]-oldPositions[0])/(oldPositions[x1*2]-oldPositions[0]);
        float ty=(base[i+1]-oldPositions[1])/(oldPositions[y1*2+1]-oldPositions[1]);
        uvs[i]=oldUvs[0]+tx*(oldUvs[x1*2]-oldUvs[0])+ty*(oldUvs[y1*2]-oldUvs[0]);
        uvs[i+1]=oldUvs[1]+tx*(oldUvs[x1*2+1]-oldUvs[1])+ty*(oldUvs[y1*2+1]-oldUvs[1]);
      }
      // The source topology owns the vertex count independently of keyforms.
      // Updating only form positions leaves the importer's four-vertex quad.
      mesh.setPositions(base.clone());mesh.setUvs(uvs);mesh.setIndices(ints((List<?>)spec.get("indices")));
      String parent=(String)spec.get("parent");if(!parent.isEmpty())mesh.setTargetDeformerGuid(deformers.get(parent).getGuid());
      var original=mesh.getDefaultKeyForm();mesh.getKeyforms().clear();
      List<Pair<CParameterGuid,float[]>> keySpecs=new ArrayList<>();
      for(Object entry:(List<?>)spec.get("bindings")) {
        Map<String,Object> binding=(Map<String,Object>)entry;
        keySpecs.add(new Pair<>(parameters.get((String)binding.get("id")).getGuid(),floats((List<?>)binding.get("keys"))));
      }
      List<CFormGuid> guids=new ArrayList<>();int order=((Number)spec.get("drawOrder")).intValue();
      Map<String,Object> opacity=(Map<String,Object>)spec.get("opacity");
      for(Object entry:(List<?>)spec.get("forms")) {
        Map<String,Object> formSpec=(Map<String,Object>)entry;
        CArtMeshForm form=original.deepCopy(new com.live2d.core.a());form.setGuid(new CFormGuid());form.setName(id+"_"+guids.size());
        float[] points=new float[base.length];int offset=((Number)formSpec.get("offset")).intValue();
        for(int i=0;i<points.length;i++)points[i]=positions.getFloat(offset+i*4);
        form.setPositions(points);form.setDrawOrder(order);form.setOpacity(opacity.containsKey("constant")?number(opacity.get("constant")):1);
        form.setCoordType(parent.isEmpty()?canvas:local);mesh.getKeyforms().add(form);guids.add(form.getGuid());
      }
      grid(mesh,keySpecs,guids);
      if(opacity.containsKey("parameter")) opacityPart(mesh,(String)opacity.get("parameter"),floats((List<?>)opacity.get("keys")),floats((List<?>)opacity.get("values")));
      mesh.setMeshUpdatedFlag__testImpl();
    }
    // Original eye/mouth drawings remain intact; the authored face alpha clips
    // their contours at small-angle extremes. The inverse flag is fixture-only.
    for (var entry: meshes.entrySet()) {
      if (entry.getKey().startsWith("eyes_") || entry.getKey().startsWith("mouth_")) {
        entry.getValue().getClipGuidList().add(meshes.get("face").getGuid());
        entry.getValue().setInvertClippingMask(Boolean.getBoolean("mio.maskInverse"));
      }
    }
    source.updateParamInstance(true);
    System.out.println("Mio bindings: "+parameters.size()+" parameters, "+deformers.size()+" rotation deformers, "+source.getAllArtMeshes().size()+" meshes");
  }
  private static List<float[]> combinations(float[][] dimensions) {
    List<float[]> result=new ArrayList<>();result.add(new float[0]);
    for(float[] keys:dimensions) {
      List<float[]> next=new ArrayList<>();for(float key:keys)for(float[] old:result){float[] a=Arrays.copyOf(old,old.length+1);a[old.length]=key;next.add(a);}result=next;
    }
    return result;
  }
  private static void rotation(String name,String parent,String[] ids,float[][] keys) throws Exception {
    CRotationDeformerSource deformer=new CRotationDeformerSource(model);deformer.setId(new CDeformerId("Mio"+name));deformer.setLocalName(name);
    if(!parent.isEmpty())deformer.setTargetDeformerGuid(deformers.get(parent).getGuid());
    model.addParameterControllableSource(deformer);
    List<CFormGuid> guids=new ArrayList<>();
    for(float[] values:combinations(keys)) {
      CRotationDeformerForm form=new CRotationDeformerForm();form.setGuid(new CFormGuid());form.set_source$cubism(deformer);
      form.setName(name+"_"+guids.size());form.setScale(1);form.setOpacity(1);form.setCoordType(parent.isEmpty()?canvas:local);
      float angle=values[0];
      if(name.equals("Body")) {
        double radians=Math.toRadians(angle);float lift=values[1];form.setOriginX(375+(float)Math.sin(radians)*lift);form.setOriginY(432-(float)Math.cos(radians)*lift);
      } else if(name.equals("Head")) { form.setOriginX(values[1]*0.1f);form.setOriginY(-127-values[2]*0.25f); }
      else {
        boolean left=name.endsWith("L");
        if(name.startsWith("Shoulder")){
          // Author clavicle lift in the parent deformer so every child keeps
          // its attachment, including third-party Cubism motion playback.
          float outward=left?angle:-angle,t=Math.max(0,Math.min(1,(outward-0.9f)/0.65f));
          float raised=t*t*(3-2*t);
          float a=Math.max(0,Math.min(1,(outward+0.65f)/0.17f));
          float b=Math.max(0,Math.min(1,(outward+0.3f)/0.22f));
          float resting=a*a*(3-2*a)*(1-b*b*(3-2*b));
          form.setOriginX((left?-69:69)+(left?12:-12)*raised);
          form.setOriginY(-112-7*resting-20*raised);
        }
        else if(name.startsWith("Elbow")){form.setOriginX(left?-58:58);form.setOriginY(98);}
        else {form.setOriginX(left?-59:59);form.setOriginY(90);}
        angle=(float)Math.toDegrees(angle);
      }
      form.setAngle(angle);deformer.getKeyforms().add(form);guids.add(form.getGuid());
    }
    List<Pair<CParameterGuid,float[]>> keySpecs=new ArrayList<>();for(int i=0;i<ids.length;i++)keySpecs.add(new Pair<>(parameters.get(ids[i]).getGuid(),keys[i]));
    grid(deformer,keySpecs,guids);deformers.put(name,deformer);
  }
  private static void opacityPart(CArtMeshSource mesh,String id,float[] keys,float[] values) throws Exception {
    CRotationDeformerSource visibility=new CRotationDeformerSource(model);
    visibility.setId(new CDeformerId("Visibility_"+mesh.getId()));visibility.setLocalName(mesh.getLocalName()+" visibility");
    visibility.setTargetDeformerGuid(mesh.getTargetDeformerGuid());model.addParameterControllableSource(visibility);
    List<CFormGuid> guids=new ArrayList<>();
    for(int i=0;i<keys.length;i++) {
      CRotationDeformerForm form=new CRotationDeformerForm();form.set_source$cubism(visibility);form.setGuid(new CFormGuid());
      form.setName(mesh.getId()+"_opacity_"+i);form.setOpacity(values[i]);form.setScale(1);form.setAngle(0);
      form.setOriginX(0);form.setOriginY(0);form.setCoordType(local);visibility.getKeyforms().add(form);guids.add(form.getGuid());
    }
    grid(visibility,List.of(new Pair<>(parameters.get(id).getGuid(),keys)),guids);mesh.setTargetDeformerGuid(visibility.getGuid());
  }

  private static void grid(ACParameterControllableSource source,List<Pair<CParameterGuid,float[]>> keys,List<CFormGuid> guids) throws Exception {
    KeyformGridSource grid=new KeyformGridSource(source);
    grid.getClass().getMethod("import",CModelSource.class,List.class,List.class).invoke(grid,model,keys,guids);
    source.setKeyformGridSource(grid);
  }
}
