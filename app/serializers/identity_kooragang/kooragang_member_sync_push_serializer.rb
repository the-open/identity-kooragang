module IdentityKooragang
  class KooragangMemberSyncPushSerializer < ActiveModel::Serializer
    attributes :external_id, :first_name, :phone_number, :campaign_id, :audience_id, :data

    def external_id
      @object.id
    end

    def first_name
      @object.first_name ? @object.first_name : ''
    end

    def phone_number
      phone_scope = instance_options[:phone_type] == 'all' ? 'phone' : instance_options[:phone_type]
      @object.send(phone_scope)
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