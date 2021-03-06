defmodule ExOAPI.Generator.Paths.Call do
  use TypedEctoSchema

  alias ExOAPI.Parser.V3.Context
  alias Context.{Operation, Parameters}

  @primary_key false

  typed_embedded_schema do
    field(:verb, :string)
    field(:name, :string)
    field(:module, :string)
    field(:module_path, :string)
    field(:required_args, {:array, :map})
    field(:optional_args, {:array, :map})
    field(:path, :string)
    field(:base_url, :string)
    field(:full_url, :string)
    embeds_one(:op, Operation)
  end

  def new(verb, path, %Context.Paths{} = paths, %Context{} = ctx) do
    case Map.get(paths, verb) do
      nil ->
        nil

      %Operation{fn_name: fn_name, module: module, module_path: module_path} = op ->
        op = maybe_merge_params(op, paths)

        {required_args, optional_args} = build_args(op)
        security_args = extract_security_args(op, ctx)

        final_required_args =
          required_args
          |> maybe_add_body_arg(op, ctx, verb)

        final_optional_args =
          optional_args
          |> maybe_add_security_args(security_args, ctx)

        base_url = base_url(op, ctx)

        %__MODULE__{
          verb: verb,
          name: fn_name,
          path: path,
          module: module,
          module_path: module_path,
          base_url: base_url,
          required_args: final_required_args,
          optional_args: final_optional_args,
          op: op
        }
    end
  end

  defp maybe_merge_params(%Operation{parameters: op_params} = op, %Context.Paths{
         parameters: path_params
       })
       when is_map(path_params) do
    %Operation{
      op
      | parameters: Map.merge(path_params, op_params)
    }
  end

  defp maybe_merge_params(op, _), do: op

  def base_url(
        %Operation{servers: _},
        %Context{servers: [%{url: url} | _]}
      ),
      do: url

  def build_args(%Operation{parameters: parameters}) do
    Enum.reduce(parameters, {[], []}, fn %Parameters{} = param, {required, optional} ->
      case make_param(param) do
        {:required, new_param} -> {[new_param | required], optional}
        {:optional, new_param} -> {required, [new_param | optional]}
      end
    end)
  end

  def make_param(%Parameters{
        required: req,
        in: in_type,
        name: name,
        schema: _schema,
        explode: explode,
        style: style
      }) do
    {
      if(req, do: :required, else: :optional),
      %{name: name, in: in_type, arg_form: make_safe_arg(name), explode: explode, style: style}
    }
  end

  # TODO figure out how to merge scopes 
  def extract_security_args(
        %Operation{security: [_ | _] = security},
        %Context{components: %Context.Components{security_schemes: s_schemes}}
      ) do
    Enum.reduce(security, [], fn security_obj, acc ->
      Enum.reduce(security_obj, acc, fn
        {k, []}, i_acc -> [Map.get(s_schemes, k) | i_acc]
        {k, _scopes}, i_acc -> [Map.get(s_schemes, k) | i_acc]
      end)
    end)
  end

  def extract_security_args(_, _), do: []

  def maybe_add_security_args(optional_args, [], _), do: optional_args

  def maybe_add_security_args(optional_args, security_list, _ctx) do
    Enum.reduce(security_list, optional_args, fn security, acc ->
      case is_security_arg?(security) do
        true -> [security | acc]
        _ -> acc
      end
    end)
  end

  def make_safe_arg(arg) do
    case ExOAPI.EctoTypes.SafeUL.cast(arg) do
      {:ok, arg} ->
        arg

      _ ->
        raise "invalid arg name: #{arg}"
    end
  end

  def is_security_arg?(%Context.Security{in: in_type}),
    do: in_type in [:header, :query]

  def maybe_add_body_arg(required_args, _, _, verb) when verb in [:get, :head, :options, :trace],
    do: required_args

  def maybe_add_body_arg(required_args, %Operation{request_body: nil}, _, _),
    do: required_args

  def maybe_add_body_arg(
        required_args,
        %Operation{
          request_body: %Context.RequestBody{
            content: content
          }
        },
        %Context{} = ctx,
        _
      ) do
    Enum.reduce_while(content, [], fn
      {k, %Context.Media{} = media}, acc ->
        {:cont, [{k, make_body_arg(media, ctx)} | acc]}

      _, acc ->
        {:cont, acc}
    end)
    |> case do
      [_ | _] = body_encodings -> [%{body: body_encodings, in: :body} | required_args]
      [] -> required_args
    end
  end

  def make_body_arg(%Context.Media{schema: %Context.Schema{ref: nil} = body_def}, _ctx),
    do: body_def

  def make_body_arg(%Context.Media{schema: %Context.Schema{ref: ref}}, ctx),
    do: ExOAPI.Generator.Helpers.extract_ref(ref, ctx)
end
