defmodule Mcsv.V3.ImageConvertedNotification do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :user_email, 1, type: :string, json_name: "userEmail"
  field :success, 2, type: :bool
  field :message, 3, type: :string
  field :input_size, 4, type: :int64, json_name: "inputSize"
  field :output_size, 5, type: :int64, json_name: "outputSize"
  field :width, 6, type: :int32
  field :height, 7, type: :int32
  field :storage_id, 8, type: :string, json_name: "storageId"
  field :original_storage_id, 9, type: :string, json_name: "originalStorageId"
  field :pdf_url, 10, type: :string, json_name: "pdfUrl"
end

defmodule Mcsv.V3.ImageConvertedResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :message, 2, type: :string
end
