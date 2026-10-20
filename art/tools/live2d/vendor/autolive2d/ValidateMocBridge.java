// Derived from autoLive2d, Copyright (c) 2026 Dongshan_Randeng, MIT.
// See LICENSE.autolive2d; adapted for locally installed Cubism Editor 5.3.04.
package autolive2d.bridge;
import java.util.List;
import java.util.ArrayList;

import com.live2d.sdk.cubism.core.CubismMoc;
import com.live2d.sdk.cubism.core.CubismModel;
import com.live2d.sdk.cubism.core.Live2DCubismCore;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

public final class ValidateMocBridge {
  public static void main(String[] args) {
    Map<String, Object> result = new LinkedHashMap<>();
    String moc3Path = args.length > 0 ? args[0] : "";

    result.put("status", "error");
    result.put("vendorDir", "");
    result.put("manifestPath", "");
    result.put("moc3Path", moc3Path);
    result.put("javaVersion", System.getProperty("java.version", ""));

    try {
      byte[] bytes = Files.readAllBytes(Path.of(moc3Path));
      result.put("consistency", Live2DCubismCore.hasMocConsistency(bytes));
      result.put("mocVersion", Live2DCubismCore.getMocVersion(bytes));

      try (CubismMoc moc = CubismMoc.instantiate(bytes)) {
        try (CubismModel model = moc.instantiateModel()) {
          result.put("parameterCount", model.getParameterViews().length);
          result.put("partCount", model.getPartViews().length);
          result.put("drawableCount", model.getDrawableViews().length);
        }
      }

      result.put("status", "ok");
    } catch (Throwable error) {
      Throwable root = unwrap(error);
      result.put("error", rootMessage(root));
    }

    System.out.println(toJson(result));
    System.exit("ok".equals(result.get("status")) ? 0 : 1);
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
}
