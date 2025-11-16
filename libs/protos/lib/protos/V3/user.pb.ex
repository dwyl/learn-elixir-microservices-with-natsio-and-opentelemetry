defmodule Mcsv.V3.EmailType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :EMAIL_TYPE_UNSPECIFIED, 0
  field :EMAIL_TYPE_WELCOME, 1
  field :EMAIL_TYPE_NOTIFICATION, 2
end

defmodule Mcsv.V3.UserRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :name, 2, type: :string
  field :email, 3, type: :string
  field :type, 4, type: Mcsv.V3.EmailType, enum: true
end

defmodule Mcsv.V3.UserResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :message, 2, type: :string
end

defmodule Mcsv.V3.StoreImageRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :image_data, 1, type: :bytes, json_name: "imageData"
  field :user_id, 2, type: :string, json_name: "userId"
  field :format, 3, type: :string
  field :original_storage_id, 4, type: :string, json_name: "originalStorageId"
  field :user_email, 5, type: :string, json_name: "userEmail"
  field :job_id, 6, type: :string, json_name: "jobId"
end

defmodule Mcsv.V3.StoreImageResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
  field :job_id, 3, type: :string, json_name: "jobId"
  field :presigned_url, 4, type: :string, json_name: "presignedUrl"
  field :size, 5, type: :int64
end

defmodule Mcsv.V3.PdfReadyNotification do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :user_email, 1, type: :string, json_name: "userEmail"
  field :job_id, 2, type: :string, json_name: "jobId"
  field :presigned_url, 3, type: :string, json_name: "presignedUrl"
  field :size, 4, type: :int64
  field :message, 5, type: :string
end

defmodule Mcsv.V3.PdfReadyResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :message, 2, type: :string
  field :user_email, 3, type: :string, json_name: "userEmail"
end

defmodule Mcsv.V3.NotifyImageConvertedResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :message, 2, type: :string
  field :user_email, 3, type: :string, json_name: "userEmail"
end
