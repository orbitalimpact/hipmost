require_relative '../lib/hipmost/user_repository'

RSpec.describe Hipmost::UserRepository do
  it "loads user data" do
    repo = described_class.new(".")
    repo.load(data)

    expect(repo.size).to eq(2)

    expect(repo[564740]).to be_a(Hipmost::UserRepository::User)
  end

  let(:data) do
    <<-JSON
      [
        {
          "User": {
            "account_type": "guest",
            "avatar": null,
            "created": "2013-12-02T18:04:15+00:00",
            "email": null,
            "id": 564740,
            "is_deleted": true,
            "mention_name": "JeffBurnsGuest",
            "name": "Jeff Burns",
            "roles": [
              "user"
            ],
            "rooms": [],
            "timezone": "America/Denver",
            "title": ""
          }
        },
        {
          "User": {
            "account_type": "guest",
            "avatar": null,
            "created": "2014-11-24T16:33:04+00:00",
            "email": null,
            "id": 1466775,
            "is_deleted": true,
            "mention_name": "JovenOrozcoGuest",
            "name": "Joven Orozco",
            "roles": [
              "user"
            ],
            "rooms": [],
            "timezone": "America/Los_Angeles",
            "title": ""
          }
        }
      ]
    JSON
  end
end
