# ExOAPI

ExOAPI is an Elixir library for generating Client SDK's from OpenAPI v3 json specs.

Note this is a very very early release of the library. It has been used with [Docusign's eSign REST](http://micaelnussbaumer.com/docusign_test/Docusign.html#content) spec, [Plaid](http://micaelnussbaumer.com/plaid_test/Plaid.html#content), and [Flagsmith](http://micaelnussbaumer.com/flagsmith-test/Flagsmith.html#content) - but not extensively.
Please check the [CAVEATS](#caveats) to be aware of possible shortcomings, non-implemented details, and possible future changes.

```elixir
ExOAPI.generate(%{
  source: Path.join([File.cwd!(), "priv/docusign_oapi.json"]),
  output_path: "/home/work-base/code/docusign_sdk",
  output_type: :app,
  title: "Docusign"
})
```

<div align="center">
     <a href="#exoapi">Description</a><span>&nbsp; |</span>
     <a href="#installation">Installation</a><span>&nbsp; |</span>
     <a href="#usage">Usage</a><span>&nbsp; |</span>
     <a href="#generator">Generator</a><span>&nbsp; |</span>
     <a href="#client">Client</a><span>&nbsp; |</span>
     <a href="#caveats">Caveats</a><span>&nbsp; |</span>
     <a href="#roadmap">Roadmap</a><span>&nbsp; |</span>
     <a href="#about">About</a><span>&nbsp; |</span>
     <a href="#copyright">Copyright</a>
</div>

### Installation

Add `ex_oapi` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_oapi, "~> 0.1.2"}
  ]
end
```

### Usage

#### Generator

```elixir
ExOAPI.generate(%{
  source: "full_path_to_an_open_api_v3_json_spec",
  output_path: "full_path_of_where_to_place_the_generated_sdk",
  output_type: :app,
  title: "AppModule.Name.To.Use"
})
```

This generates a default SDK where optional arguments are passed as option lists.
You can instead generated it with either `positional arguments` instead, or in a `map` form.

```elixir
ExOAPI.generate(%{
  source: "full_path_to_an_open_api_v3_json_spec",
  output_path: "full_path_of_where_to_place_the_generated_sdk",
  output_type: :app,
  title: "AppModule.Name.To.Use",
  generator: %{optional_args: :positional}
})
```


The final modules for the API will contain functions of the given form:

```elixir
@doc """
  **summary**: Gets the status of a single envelope.

  **description**: Retrieves the overall status for the specified envelope.
  To get the status of a list of envelopes, use
  [Envelope: listStatusChanges ](https://developers.docusign.com/docs/esign-rest-api/reference/envelopes/envelopes/liststatuschanges/).

  ### Related topics

  - [How to get envelope information](https://developers.docusign.com/docs/esign-rest-api/how-to/get-envelope-information/)


  """
  @type get_envelope_opts :: {:include, String.t()} | {:advanced_update, String.t()}
  @spec get_envelope(
          client :: ExOAPI.Client.t(),
          envelope_id :: String.t(),
          account_id :: String.t(),
          list(get_envelope_opts())
        ) :: {:ok, any()} | {:error, any()}
  def get_envelope(%ExOAPI.Client{} = client, envelope_id, account_id, opts \\ []) do
    client
    |> ExOAPI.Client.set_module(Docusign.SDK)
    |> ExOAPI.Client.add_method(:get)
    |> ExOAPI.Client.add_base_url("https://www.docusign.net/restapi", :exoapi_default)
    |> ExOAPI.Client.add_path("/v2.1/accounts/{accountId}/envelopes/{envelopeId}")
    |> ExOAPI.Client.replace_in_path("envelopeId", envelope_id)
    |> ExOAPI.Client.replace_in_path("accountId", account_id)
    |> ExOAPI.Client.add_arg_opts(:keyword, :query, opts, [
      {:include, "include", "form", true},
      {:advanced_update, "advanced_update", "form", true}
    ])
    |> ExOAPI.Client.request()
  end
```

And schemas of the following form:

```elixir
defmodule Flagsmith.Schemas.FeatureStateSerializerFull do
  use TypedEctoSchema
  import Ecto.Changeset

  @type params :: map()

  @moduledoc """
  **:enabled** :: *:boolean*


  **:environment** :: *:integer*


  **:feature** :: *Flagsmith.Schemas.Feature*


  **:feature_segment** :: *:integer*


  **:feature_state_value** :: *:string*


  **:id** :: *:integer*


  **:identity** :: *:integer*


  """

  @primary_key false
  typed_embedded_schema do
    field(:enabled, :boolean)

    field(:environment, :integer)

    embeds_one(:feature, Flagsmith.Schemas.Feature)

    field(:feature_segment, :integer)

    field(:feature_state_value, :string)

    field(:id, :integer)

    field(:identity, :integer)
  end

  @spec changeset(params()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), params()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [
      :identity,
      :id,
      :feature_state_value,
      :feature_segment,
      :environment,
      :enabled
    ])
    |> cast_embed(:feature, required: true)
  end
end
```

With proper `embeds_one`, `embeds_many`, `Ecto.Enum`, etc, and changeset validations appropriate to it.

#### Client

To use the generated SDK usually you will populate the `lib/NAME_OF_LIB.ex` file with some functions that wrap the instantiation of the needed bits to your client.

For instance, to use docusign's SDK that requires an `Authorization` header in most, you could do:

```elixir
auth_token = go_get_my_auth_token_somehow()

client =
  %ExOAPI.Client{}
  |> ExOAPI.Client.add_header("Authorization", "Bearer #{auth_token}")
  |> ExOAPI.Client.add_middleware(Tesla.Middleware.JSON)
  |> ExOAPI.Client.add_base_url("https://demo.docusign.net/restapi/")
```

And now you could use this client for all subsequent requests.
The client functions are exposed from `lib/ex_oapi/client.ex`. Underneath ExOAPI uses `Tesla` so you can configure tesla itself and also set things such as middlewares in the tesla format. Documentation is lacking atm and there's probably some work to polish the interface a bit but basically you can do:

```elixir
add_options(client, opts) # to add options to be passed to the underlying tesla adapter
add_middleware(client, {_, _} | Middleware) # to add a tesla middleware
set_adapter(client, {_, _}) # to set a runtime adapter for the client
add_base_url(client, url) # to set the base_url the client will use
add_header(client, header_string, header_value) # add an header
add_query(client, key, value) # add a query parameter
```

You can also set a response handler (besides middlewares) that deals with the request response. This has no interface yet but you can set it manually on the client. It can accept `mfa` tuples or 2 arity function captures.

```elixir
client = %ExOAPI.Client{client | response_handler: {Module, :fun, [extra_args]}}
client = %ExOAPI.Client{client | response_handler: {Module, :fun}}
client = %ExOAPI.Client{client | response_handler: &SomeModule.capture/2}
```

All of them get passed the `response` as the first argument, the `client` struct used in the request as the second, and, in case of the 3 sized tuple with anything other than an empty list, any arguments there specified.

Although this is not yet finished it allows you to deal with the tesla responses as you wish and can be set as part of your client instantiation.

If no response function is set the default is to parse them back when in JSON form to a schema if there's is one specified on the `path` spec, and in case the schema doesn't pass validation the original json body is returned (this behaviour will change and be configurable, the reason is that some specs specify schemas as the response that are either plainly wrong, or have required fields in their definition that are not present when receiving responses that use those schemas, and that makes validation fail)


### Caveats

Currently there's no task like interface, so you'll need to wrap this lib or use it from an existing app to which you add the dependency and then call from an iex shell.

Although there's functionality to generate non-app SDK's (i.e. just the modules) it is not in its final form. The best would be to generate the app version and just move the contents of the `lib/` directory.

Generating a SDK restricted to a set of `paths` already works, and ditches all unused schemas, while being able to track deeply nested refs in order to include all needed schemas somehow mentioned in the desired paths. Nonetheless it only supports being given the exact paths to include and is going to be re-written to support, partial paths, regexes and other ways of filtering, such as by tags.

Manipulating the resulting spec schemas prior to dumping them also has hooks but this can be done outside by manipulating the json itself prior to feeding it to `ExOAPI` and as of now it's the way you should go, because this functionality is not yet stable, nor documented, it should not be relied upon.

While most of the important and common OpenAPI 3 spec is covered, certain things aren't yet:

- `anyOf`, `noneOf`, `oneOf`, `not` (`allOf` is implemented as it was the only one I've ran into yet)
- `discriminator`
- support and validation for payloads other than `json`
- xml related functionality
- callback's related functionality
- replacement of relative url's in descriptions and external docs by automatic `server` config ones
- `ref`s that point to external urls are currently not supported

There's no support for other types of payloads besides json. You can pass whatever as a body to a given API function that takes one but it won't be validated, nor handled specifically, this includes files and such.

Besides that most of the internals will be re-written, but since it's already been useful to generate usable clients I thought it would be ok to share as is for the moment being.

If you give it a try and run into a problem or wish to contribute, feel free to open an issue to discuss it.

<div id="about"></div>

## About

![Cocktail Logo](https://github.com/mnussbaumer/cssex/blob/master/logo/cocktail_logo.png?raw=true "Cocktail Logo")

[© rooster image in the cocktail logo](https://commons.wikimedia.org/wiki/User:LadyofHats)

<div id="copyright"></div>

## Copyright

```
Copyright [2021-∞] [Micael Nussbaumer]

Permission is hereby granted, free of charge, to any person obtaining a copy of this 
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify, 
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to 
permit persons to whom the Software is furnished to do so, subject to the following 
conditions:

The above copyright notice and this permission notice shall be included in all copies
or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
