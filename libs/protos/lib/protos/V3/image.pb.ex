defmodule Mcsv.V3.S3Reference do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :bucket, 1, type: :string
  field :key, 2, type: :string
  field :presigned_url, 3, type: :string, json_name: "presignedUrl"
end

defmodule Mcsv.V3.ImageConversionRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof :source, 0

  field :user_id, 1, type: :string, json_name: "userId"
  field :user_email, 2, type: :string, json_name: "userEmail"
  field :image_data, 10, type: :bytes, json_name: "imageData", oneof: 0
  field :image_url, 3, type: :string, json_name: "imageUrl", oneof: 0, deprecated: true
  field :s3_ref, 11, type: Mcsv.V3.S3Reference, json_name: "s3Ref", oneof: 0
  field :input_format, 4, type: :string, json_name: "inputFormat"
  field :pdf_quality, 5, type: :string, json_name: "pdfQuality"
  field :strip_metadata, 6, type: :bool, json_name: "stripMetadata"
  field :max_width, 7, type: :int32, json_name: "maxWidth"
  field :max_height, 8, type: :int32, json_name: "maxHeight"
  field :job_id, 9, type: :string, json_name: "jobId"
end

defmodule Mcsv.V3.ImageConversionResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
  field :input_size, 4, type: :int64, json_name: "inputSize"
  field :output_size, 5, type: :int64, json_name: "outputSize"
  field :width, 6, type: :int32
  field :height, 7, type: :int32
  field :job_id, 8, type: :string, json_name: "jobId"
  field :pdf_url, 9, type: :string, json_name: "pdfUrl"
  field :user_email, 10, type: :string, json_name: "userEmail"
end
