function percent(valueTimes100) {
  let whole = valueTimes100 div 100;
  let frac = valueTimes100 % 100;
  if (frac < 10) return whole + ".0" + frac + "%";
  return whole + "." + frac + "%";
}

function ms(value) {
  return value + " ms";
}

function incidentId(n) {
  return "INC-" + n;
}

function nonEmpty(value) {
  return value != null && value != "";
}

exports { percent, ms, incidentId, nonEmpty };
