D = Steep::Diagnostic

target :lib do
  signature "sig"
  check "lib"
  library "net-http"

  configure_code_diagnostics(D::Ruby.strict) do |config|
    config[D::Ruby::UnknownConstant] = :information
  end
end
