module IdentityKooragang
  class KooragangMemberSyncPushSerializer < ActiveModel::Serializer
    attributes :external_id, :first_name, :phone_number, :campaign_id, :audience_id, :data

    def external_id
      @object.id
    end

    def phone_number
      @object.send(instance_options[:phone_type])
    end

    def campaign_id
      instance_options[:campaign_id]
    end

    def audience_id
      instance_options[:audience_id]
    end

    def data
      @object.flattened_custom_fields.to_json
    end
  end
end