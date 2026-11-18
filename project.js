.pragma library

// Only the request's recorded attribution supplies a product name.
function label(request) {
  var project = request && typeof request.project === "string" ? request.project.trim() : ""
  return request && request.projectAttribution === "known" && project !== ""
    ? project.toUpperCase() : "PROJECT UNKNOWN"
}

function reason(request) {
  if (label(request) !== "PROJECT UNKNOWN") return ""
  var reason = request && typeof request.projectUnresolvedReason === "string"
    ? request.projectUnresolvedReason.trim() : ""
  return reason !== "" ? reason : "No product was recorded for this request."
}
