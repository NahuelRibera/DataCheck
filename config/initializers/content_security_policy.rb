# Be sure to restart your server when you modify this file.

# Content security policy for the web interface. The pages load one same-origin
# script and use no inline scripts, so scripts are limited to 'self' (no
# 'unsafe-inline'). Views still use inline style="" attributes, so only the
# style attribute directive allows inline styles; <style> elements and
# stylesheets remain restricted to 'self'.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.script_src      :self
    policy.style_src       :self
    policy.style_src_attr  :unsafe_inline
    policy.img_src         :self, :data
    policy.font_src        :self, :data
    policy.connect_src     :self
    policy.object_src      :none
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :none
  end
end
