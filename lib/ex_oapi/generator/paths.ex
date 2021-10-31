defmodule ExOAPI.Generator.Paths do
  use TypedEctoSchema

  alias ExOAPI.Parser.V3.Context
  alias ExOAPI.Generator.Paths.Call
  @verbs ExOAPI.Generator.Helpers.http_verbs()

  @primary_key false

  typed_embedded_schema do
    embeds_one(:ctx, Context)
    embeds_many(:calls, Call)
  end

  def new(path, %Context{paths: paths} = ctx) do
    paths
    |> Map.get(path)
    |> build_path_calls(path, ctx)
  end

  def build_path_calls(path_definition, path, ctx) do
    Enum.reduce(@verbs, [], fn verb, acc ->
      case Call.new(verb, path, path_definition, ctx) do
        nil -> acc
        path_call -> [path_call | acc]
      end
    end)
    |> Enum.reverse()
  end
end
