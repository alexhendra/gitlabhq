require 'spec_helper'

describe Gitlab::LDAP::Access do
  let(:access) { Gitlab::LDAP::Access.new }
  let(:user) { create(:user) }
  let(:group) { create(:group, ldap_cn: 'oss', ldap_access: Gitlab::Access::DEVELOPER) }

  before do
    group
  end

  describe :add_user_to_groups do
    it "should add user to group" do
      access.add_user_to_groups(user.id, "oss")
      member = group.members.first
      member.user.should == user
      member.group_access.should == Gitlab::Access::DEVELOPER
    end

    it "should respect higher permissions" do
      group.add_owner(user)
      access.add_user_to_groups(user.id, "oss")
      group.owners.should include(user)
    end

    it "should update lower permissions" do
      group.add_user(user, Gitlab::Access::REPORTER)
      access.add_user_to_groups(user.id, "oss")
      member = group.members.first
      member.user.should == user
      member.group_access.should == Gitlab::Access::DEVELOPER
    end
  end

  describe :update_user_email do
    let(:user_ldap) { create(:user, provider: 'ldap', extern_uid: "66048")}

    it "should not update email if email attribute is not set" do
      entry = Net::LDAP::Entry.new
      Gitlab::LDAP::Adapter.any_instance.stub(:user) { Gitlab::LDAP::Person.new(entry) }
      updated = access.update_email(user_ldap)
      updated.should == false
    end

    it "should not update the email if the user has the same email in GitLab and in LDAP" do
      entry = Net::LDAP::Entry.new
      entry['mail'] = [user_ldap.email]
      Gitlab::LDAP::Adapter.any_instance.stub(:user) { Gitlab::LDAP::Person.new(entry) }
      updated = access.update_email(user_ldap)
      updated.should == false
    end

    it "should not update the email if the user has the same email GitLab and in LDAP, but with upper case in LDAP" do
      entry = Net::LDAP::Entry.new
      entry['mail'] = [user_ldap.email.upcase]
      Gitlab::LDAP::Adapter.any_instance.stub(:user) { Gitlab::LDAP::Person.new(entry) }
      updated = access.update_email(user_ldap)
      updated.should == false
    end

    it "should update the email if the user email is different" do
      entry = Net::LDAP::Entry.new
      entry['mail'] = ["new_email@example.com"]
      Gitlab::LDAP::Adapter.any_instance.stub(:user) { Gitlab::LDAP::Person.new(entry) }
      updated = access.update_email(user_ldap)
      updated.should == true
    end
  end

  describe :allowed? do
    subject { access.allowed?(user) }

    context 'when the user cannot be found' do
      before { Gitlab::LDAP::Person.stub(find_by_dn: nil) }

      it { should be_false }
    end

    context 'when the user is found' do
      before { Gitlab::LDAP::Person.stub(find_by_dn: :ldap_user) }

      context 'and the Active Directory disabled flag is set' do
        before { Gitlab::LDAP::Person.stub(active_directory_disabled?: true) }

        it { should be_false }
      end

      context 'and the Active Directory disabled flag is not set' do
        before { Gitlab::LDAP::Person.stub(active_directory_disabled?: false) }

        it { should be_true }
      end
    end
  end

  describe :update_admin_status do
    let(:gitlab_user) { create(:user, provider: 'ldap', extern_uid: "admin2")}
    let(:gitlab_admin) { create(:admin, provider: 'ldap', extern_uid: "admin2")}

    before do
      Gitlab.config.ldap['admin_group'] = "GLAdmins"
      ldap_user_entry = Net::LDAP::Entry.new
      Gitlab::LDAP::Adapter.any_instance.stub(:user) { Gitlab::LDAP::Person.new(ldap_user_entry) }
      Gitlab::LDAP::Person.any_instance.stub(:uid) { 'admin2' }
    end

    it "should give admin privileges to an User" do
      admin_group = Net::LDAP::Entry.from_single_ldif_string(
%Q{dn: cn=#{Gitlab.config.ldap['admin_group']},ou=groups,dc=bar,dc=com
cn: #{Gitlab.config.ldap['admin_group']}
description: GitLab admins
gidnumber: 42
memberuid: admin1
memberuid: admin2
memberuid: admin3
objectclass: top
objectclass: posixGroup
})
      Gitlab::LDAP::Adapter.any_instance.stub(:group) { Gitlab::LDAP::Group.new(admin_group) }
      expect(gitlab_user.admin?).to be false
      access.update_admin_status(gitlab_user)
      expect(gitlab_user.admin?).to be true
    end

    it "should remove admin privileges from an User" do
      admin_group = Net::LDAP::Entry.from_single_ldif_string(
%Q{dn: cn=#{Gitlab.config.ldap['admin_group']},ou=groups,dc=bar,dc=com
cn: #{Gitlab.config.ldap['admin_group']}
description: GitLab admins
gidnumber: 42
memberuid: admin1
memberuid: admin3
objectclass: top
objectclass: posixGroup
})
      Gitlab::LDAP::Adapter.any_instance.stub(:group) { Gitlab::LDAP::Group.new(admin_group) }
      expect(gitlab_admin.admin?).to be true
      access.update_admin_status(gitlab_admin)
      expect(gitlab_admin.admin?).to be false
    end
  end
end
