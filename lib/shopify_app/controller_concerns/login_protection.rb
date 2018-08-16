module ShopifyApp
  module LoginProtection
    extend ActiveSupport::Concern

    class ShopifyDomainNotFound < StandardError; end

    included do
      after_action :set_test_cookie if ShopifyApp.configuration.embedded_app?
      rescue_from ActiveResource::UnauthorizedAccess, :with => :close_session
    end

    def shopify_session
      return redirect_to_login unless shop_session
      clear_top_level_oauth_cookie

      begin
        ShopifyAPI::Base.activate_session(shop_session)
        yield
      ensure
        ShopifyAPI::Base.clear_session
      end
    end

    def shop_session
      return unless session[:shopify]
      @shop_session ||= ShopifyApp::SessionRepository.retrieve(session[:shopify])
    end

    def login_again_if_different_shop
      if shop_session && params[:shop] && params[:shop].is_a?(String) && (shop_session.url != params[:shop])
        clear_shop_session
        redirect_to_login
      end
    end

    protected

    def redirect_to_login
      if request.xhr?
        head :unauthorized
      else
        if request.get?
          session[:return_to] = "#{request.path}?#{sanitized_params.to_query}"
        end
        redirect_to login_url
      end
    end

    def close_session
      clear_shop_session
      redirect_to login_url
    end

    def clear_shop_session
      session[:shopify] = nil
      session[:shopify_domain] = nil
      session[:shopify_user] = nil
    end

    def login_url(no_cookie_redirect: false)
      url = ShopifyApp.configuration.login_url

      query_params = {}
      query_params[:shop] = sanitized_params[:shop] if params[:shop].present?
      query_params[:no_cookie_redirect] = true if no_cookie_redirect

      url = "#{url}?#{query_params.to_query}" if query_params.present?
      url
    end

    def fullpage_redirect_to(url)
      if ShopifyApp.configuration.embedded_app?
        render 'shopify_app/shared/redirect', layout: false, locals: { url: url, current_shopify_domain: current_shopify_domain }
      else
        redirect_to url
      end
    end

    def current_shopify_domain
      shopify_domain = sanitized_shop_name || session[:shopify_domain]
      return shopify_domain if shopify_domain.present?

      raise ShopifyDomainNotFound
    end

    def sanitized_shop_name
      @sanitized_shop_name ||= sanitize_shop_param(params)
    end

    def sanitize_shop_param(params)
      return unless params[:shop].present?
      ShopifyApp::Utils.sanitize_shop_domain(params[:shop])
    end

    def sanitized_params
      request.query_parameters.clone.tap do |query_params|
        if params[:shop].is_a?(String)
          query_params[:shop] = sanitize_shop_param(params)
        end
      end
    end

    def set_test_cookie
      session['shopify.cookies_persist'] = true
    end

    def clear_top_level_oauth_cookie
      session.delete('shopify.top_level_oauth')
    end

    def set_top_level_oauth_cookie
      session['shopify.top_level_oauth'] = true
    end
  end
end
