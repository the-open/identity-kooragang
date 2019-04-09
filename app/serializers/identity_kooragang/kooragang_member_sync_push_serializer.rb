module IdentityKooragang
  class KooragangMemberSyncPushSerializer < ActiveModel::Serializer
    attributes :external_id, :first_name, :phone_number, :campaign_id, :audience_id, :data, :callable

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
      data = @object.flattened_custom_fields
      if instance_options[:include_rsvped_events]
        rsvps = EventRsvp.where(member_id: @object.id)
                         .joins(:event)
                         .where('events.start_time > now()')
                         .where("events.data->>'status' = 'published'")
        data["upcoming_rsvps"] = rsvps.each_with_index.map{|rsvp, index|
          "#{index+1}. #{summarise_event(rsvp.event)}"
        }.join("\n")
      end
      data.to_json
    end

    def callable
      true
    end

    private

    def summarise_event(event)
      start_time = Time.parse(event.data['start_time']) rescue event.start_time
      summary = "#{event.name} at #{event.location} at #{start_time.strftime('%H:%M on %F')}"
      if path = event.data['path']
        summary += " (https://action.getup.org.au#{path})"
      end
      summary
    end
  end
end
