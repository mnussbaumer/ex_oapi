defmodule ExOAPI.EctoTypes.Style do
  @moduledoc """
  """
  use ExOAPI.EctoTypes.TypedEnum,
    values: [
      :matrix,
      :label,
      :form,
      :simple,
      :spaceDelimited,
      :pipeDelimited,
      :deepObject
    ]
end
