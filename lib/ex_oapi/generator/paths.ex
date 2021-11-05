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

  def new(path, %Context{paths: paths} = ctx, acc) do
    paths
    |> Map.get(path)
    |> build_path_calls(path, ctx, acc)
  end

  def build_path_calls(path_definition, path, ctx, acc) do
    Enum.reduce(@verbs, acc, fn verb, acc ->
      case Call.new(verb, path, path_definition, ctx) do
        nil ->
          acc

        %{module: module, module_path: module_path} = path_call ->
          Map.update(acc, [module, module_path], [path_call], fn prev -> [path_call | prev] end)
      end
    end)
  end
end
