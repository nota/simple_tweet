# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature "sig"

  check "lib"

  configure_code_diagnostics do |hash|
    hash[D::Ruby::MethodDefinitionMissing] = :warning
    hash[D::Ruby::UnknownConstant] = :information
  end
end
