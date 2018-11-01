FactoryBot.define do
  factory :search do
    factory :search_everyone do
      rules do
        {
          'include' => {
            'condition' => 'AND', 'rules' => [{
              'id' => 'everyone', 'field' => 'everyone', 'type' => 'string', 'operator' => 'equal', 'value' => 'on'
            }]
          },
          'exclude' => {
            'condition' => 'OR', 'rules' => [{
              'id' => 'noone', 'field' => 'noone', 'type' => 'string', 'operator' => 'equal', 'value' => 'on'
            }]
          }
        }
      end
    end

    factory :search_just_james do
      rules do
        {
          'include' => {
            'condition' => 'AND', 'rules' => [{
              'id' => 'name-contains', 'field' => 'name-contains', 'type' => 'string', 'input' => 'text', 'operator' => 'contains', 'value' => 'James'
            }]
          },
          'exclude' => {
            'condition' => 'OR', 'rules' => [{
              'id' => 'noone', 'field' => 'noone', 'type' => 'string', 'operator' => 'equal', 'value' => 'on'
            }]
          }
        }
      end
    end

    factory :search_any_phones do
      rules do
        { 'include' => { 'condition' => 'AND', 'rules' => [{ 'id' => 'has-phone', 'field' => 'has-phone', 'type' => 'string', 'operator' => 'equal', 'value' => '' }] }, 'exclude' => { 'condition' => 'OR', 'rules' => [{ 'id' => 'noone', 'field' => 'noone', 'type' => 'string', 'operator' => 'equal', 'value' => 'on' }] } }
      end
    end
  end
end
