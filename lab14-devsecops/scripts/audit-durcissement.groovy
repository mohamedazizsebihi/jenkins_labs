// Lab 14 - tâche 12 : audit du durcissement Jenkins (exécuté par POST /scriptText, droit Overall/Administer)
import jenkins.model.Jenkins
import hudson.security.Permission

def j = Jenkins.get()
int ko = 0
def check = { String label, boolean good, def value ->
    if (!good) ko++
    println String.format('%-5s %-40s %s', good ? '[OK]' : '[KO]', label, value)
}

check('Sécurité activée', j.isUseSecurity(), j.isUseSecurity())
check('Remember-me désactivé', j.isDisableRememberMe(), "disableRememberMe=${j.isDisableRememberMe()}")
def fmt = j.getMarkupFormatter()
check('Formateur texte brut', fmt instanceof hudson.markup.EscapedMarkupFormatter, fmt?.getClass()?.getSimpleName())

boolean agentCtl = true
String agentInfo = 'toujours actif (non désactivable depuis Jenkins 2.326)'
try {
    def rule = j.getInjector().getInstance(Class.forName('jenkins.security.s2m.AdminWhitelistRule'))
    agentCtl = !rule.getMasterKillSwitch()
    agentInfo = "masterKillSwitch=${rule.getMasterKillSwitch()}"
} catch (Throwable t) { }
check('Contrôle agent -> contrôleur', agentCtl, agentInfo)

check('Port TCP agents inbound fermé', j.getSlaveAgentPort() == -1, "slaveAgentPort=${j.getSlaveAgentPort()}")

def tok = jenkins.security.apitoken.ApiTokenPropertyConfiguration.get()
check('Jetons legacy interdits', !tok.isCreationOfLegacyTokenEnabled() && !tok.isTokenGenerationOnCreationEnabled(),
      "creationLegacy=${tok.isCreationOfLegacyTokenEnabled()}, generationAuto=${tok.isTokenGenerationOnCreationEnabled()}")

def sshd = j.getPluginManager().getPlugin('sshd')
def sshdPort = null
if (sshd != null) { sshdPort = j.getDescriptor('org.jenkinsci.main.modules.sshd.SSHD')?.getPort() }
check('SSHD désactivé', sshd == null || sshdPort == -1, sshd == null ? 'module sshd non installé (aucun port SSH)' : "port=${sshdPort}")

check('CSRF (crumb) actif', j.getCrumbIssuer() != null, j.getCrumbIssuer()?.getClass()?.getSimpleName())
check('Exécuteurs du contrôleur = 0', j.getNumExecutors() == 0, "numExecutors=${j.getNumExecutors()}")

def strat = j.getAuthorizationStrategy()
check('Stratégie d autorisation', !(strat instanceof hudson.security.AuthorizationStrategy.Unsecured) &&
      !(strat instanceof hudson.security.FullControlOnceLoggedInAuthorizationStrategy), strat.getClass().getName())

def anon = Permission.getAll().findAll { p -> p.getEnabled() && j.getACL().hasPermission2(Jenkins.ANONYMOUS2, p) }
check('Aucun droit pour anonyme', anon.isEmpty(), anon.isEmpty() ? 'aucun' : anon.collect { it.getId() }.join(', '))

println ''
println "Bilan : ${ko == 0 ? 'conforme' : ko + ' point(s) à traiter'}"
