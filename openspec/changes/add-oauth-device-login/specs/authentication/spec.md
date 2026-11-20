# Spec Delta

## MODIFIED Requirements

### Requirement: Login method selection
The client SHALL request `GET /_matrix/client/v3/login` and offer only login methods it supports and the server advertises. Supported methods are password (`m.login.password`), SSO (`m.login.sso`) and OAuth device login (`oauth_device`, advertised in the server's OAuth auth metadata instead of the login flows). SSO SHALL only be offered when the server also advertises `m.login.token`, which is needed to exchange the SSO login token. When OAuth device login is available the client SHALL use it without asking, unless the `login_method` option names another method.

#### Scenario: Only password is offered
- **WHEN** the server advertises `m.login.password` and not `m.login.sso`, and OAuth device login is unavailable
- **THEN** the client uses password login without asking which method to use

#### Scenario: Only SSO is offered
- **WHEN** the server advertises `m.login.sso` and `m.login.token` but not `m.login.password`, and OAuth device login is unavailable
- **THEN** the client uses SSO login without asking which method to use

#### Scenario: SSO is offered without token login
- **WHEN** the server advertises `m.login.sso` but not `m.login.token`
- **THEN** the client does not offer SSO

#### Scenario: Both password and SSO are offered
- **WHEN** the server advertises `m.login.password`, `m.login.sso` and `m.login.token`, and OAuth device login is unavailable
- **THEN** the client asks the user to choose between password and SSO

#### Scenario: OAuth device login is preferred
- **WHEN** OAuth device login is available, whatever else the server advertises
- **THEN** the client uses OAuth device login without asking which method to use

#### Scenario: OAuth device login only
- **WHEN** OAuth device login is available and the server advertises no `m.login.password` or `m.login.sso` flow
- **THEN** the client uses OAuth device login and does not report an unsupported server

#### Scenario: Method forced by the user
- **GIVEN** `login_method` is set to `password`, `sso` or `oauth_device`
- **WHEN** the server supports that method
- **THEN** the client uses it without asking, even when another method would be preferred

#### Scenario: Forced method is not supported by the server
- **GIVEN** `login_method` names a method the server does not offer
- **WHEN** the user starts a login
- **THEN** the client shows an error naming the method and the methods the server offers, and does not log in

#### Scenario: No supported method is offered
- **WHEN** the server advertises neither `m.login.password` nor `m.login.sso`, and OAuth device login is unavailable
- **THEN** the client shows an error naming the advertised flow types and does not log in

#### Scenario: Login flows cannot be fetched
- **WHEN** the `GET /_matrix/client/v3/login` request fails
- **THEN** the client shows an error that includes the homeserver URL and does not log in
