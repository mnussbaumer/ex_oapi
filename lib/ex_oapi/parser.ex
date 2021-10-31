defmodule ExOAPI.Parser do
  @moduledoc """
  A library for generating HTTP client modules conforming to an OpenAPI v3 spec.
  """

  def ex_oapi_paths(), do: :ex_oapi_paths
  def ex_oapi_schemas(), do: :ex_oapi_schemas
  def ex_oapi_cull_schemas(), do: :ex_oapi_cull_schemas?
  def ex_oapi_skipped_schemas(), do: :ex_oapi_skipped_schemas
  def ex_oapi_reinsert_schemas(), do: :ex_oapi_reinsert_schemas
end
